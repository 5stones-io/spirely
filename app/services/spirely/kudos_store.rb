module Spirely
  # The Kudos store for one church (5ST-63): placing orders online or at a
  # staff checkout, handing them over, and cancelling with a refund.
  #
  # Every order locks the person first, then the items in id order, so two
  # redemptions can't both take the last item or spend the same points —
  # and the lock order is always the same, so they can't deadlock.
  class KudosStore
    MAX_QUANTITY = 20
    MAX_CODES_AT_ONCE = 1_000

    def initialize(church)
      @church = church
      @kudos  = Kudos.new(church)
    end

    # Items a kid or an adult can see in the store, in staff's order.
    def items_for(kid:)
      @church.store_items.visible.ordered.includes(image_attachment: :blob).select { |item| item.for?(kid: kid) }
    end

    # Order online. Physical items wait for pickup; digital ones are
    # delivered straight away.
    def redeem!(pco_person_id:, item_id:, quantity: 1, by_account: nil)
      place!(pco_person_id, [{ item_id: item_id, quantity: quantity }], channel: "online", by_account: by_account).first
    end

    # Staff checkout: everything is handed over on the spot.
    def checkout!(pco_person_id:, lines:, by_account:)
      raise Kudos::Error, "Pick at least one item." if Array(lines).empty?

      place!(pco_person_id, lines, channel: "checkout", by_account: by_account)
    end

    def fulfill!(order, by_account:)
      order.with_lock do
        raise Kudos::Error, "That order was already #{order.status}." unless order.pending?

        order.update!(status: "fulfilled", fulfilled_at: Time.current, fulfilled_by_name: name_of(by_account))
      end
      order
    end

    # Pending orders only — anything already handed over or delivered
    # can't come back. Refunds the points and puts the stock back.
    def cancel!(order, by_account:)
      PointsEntry.transaction do
        order.lock!
        raise Kudos::Error, "That order was already #{order.status}." unless order.pending?

        item = order.item.lock!
        item.update!(stock: item.stock + order.quantity) if item.stock
        refund = @church.points_entries.create!(
          person: order.person, points: order.points, source: "refund", note: "Refund · #{line_name(item, order.quantity)}",
          occurred_on: ChurchTime.today(@church),
        )
        order.update!(status: "cancelled", cancelled_at: Time.current, cancelled_by_name: name_of(by_account),
                      refund_entry: refund)
      end
      order
    end

    # Adds codes to a code item's pool, one per line. Blank lines and codes
    # already in the pool are skipped. Returns how many were added.
    def add_codes!(item, text)
      raise Kudos::Error, "Only code items have a pool of codes." unless item.kind == "code"

      codes = text.to_s.lines.map(&:strip).reject(&:empty?).uniq
      raise Kudos::Error, "Add up to #{MAX_CODES_AT_ONCE.to_fs(:delimited)} codes at a time." if codes.size > MAX_CODES_AT_ONCE
      raise Kudos::Error, "Codes can be up to 120 characters." if codes.any? { |c| c.length > 120 }
      return 0 if codes.empty?

      now = Time.current
      rows = codes.map { |c| { church_id: @church.id, item_id: item.id, code: c, created_at: now, updated_at: now } }
      StoreCode.insert_all(rows, unique_by: [:item_id, :code]).length
    end

    private

    # The person is looked up (or created) before the transaction, since
    # creating them can race another request and needs to retry outside it.
    def place!(pco_person_id, lines, channel:, by_account:)
      person = @kudos.person_for!(pco_person_id)
      PointsEntry.transaction do
        person.lock!

        wanted = Array(lines).map { |l| [l[:item_id].to_i, quantity_of(l[:quantity])] }
        items  = @church.store_items.where(id: wanted.map(&:first)).order(:id).lock.index_by(&:id)
        wanted.each do |item_id, quantity|
          item = items[item_id] or raise Kudos::Error, "That item isn't in the store anymore."
          check_available!(item, person, quantity)
        end

        total   = wanted.sum { |item_id, quantity| items[item_id].points * quantity }
        balance = @kudos.totals(person)[:balance]
        if total > balance
          raise Kudos::Error, "#{person.first_name} has #{balance.to_fs(:delimited)} #{balance == 1 ? "point" : "points"} " \
                              "— that's #{total.to_fs(:delimited)}."
        end

        wanted.map { |item_id, quantity| create_order!(person, items[item_id], quantity, channel, by_account) }
      end
    end

    def quantity_of(value)
      quantity = Integer(value.presence || 1, exception: false)
      raise Kudos::Error, "Pick how many, from 1 to #{MAX_QUANTITY}." unless quantity&.between?(1, MAX_QUANTITY)

      quantity
    end

    def check_available!(item, person, quantity)
      raise Kudos::Error, "#{item.name} isn't in the store right now." if item.hidden?
      raise Kudos::Error, "#{item.name} is just for #{item.audience}." unless item.for?(kid: !!person.child)

      if item.per_person_limit
        had = person.store_orders.not_cancelled.where(item: item).sum(:quantity)
        if had + quantity > item.per_person_limit
          left = [item.per_person_limit - had, 0].max
          raise Kudos::Error, left.zero? ? "#{person.first_name} already has the most #{item.name} allowed." :
                                           "#{person.first_name} can get #{left} more #{item.name}."
        end
      end

      remaining = item.remaining
      return if remaining.nil? || remaining >= quantity

      raise Kudos::Error, remaining.zero? ? "#{item.name} is sold out." : "Only #{remaining} #{item.name} left."
    end

    def create_order!(person, item, quantity, channel, by_account)
      handed_over = channel == "checkout" || item.digital?
      order = @church.store_orders.create!(
        person: person, item: item, quantity: quantity, points: item.points * quantity, channel: channel,
        status: handed_over ? "fulfilled" : "pending", fulfilled_at: (Time.current if handed_over),
        fulfilled_by_name: (name_of(by_account) if channel == "checkout"),
        placed_by_account: by_account, placed_by_name: name_of(by_account),
      )
      item.update!(stock: item.stock - quantity) if item.stock
      if item.kind == "code"
        item.codes.where(order_id: nil).order(:id).limit(quantity).update_all(order_id: order.id, updated_at: Time.current)
      end

      @church.points_entries.create!(
        person: person, points: -order.points, source: "redemption", source_type: StoreOrder.polymorphic_name,
        source_id: order.id, note: line_name(item, quantity), occurred_on: ChurchTime.today(@church),
      )
      order
    end

    def line_name(item, quantity) = quantity > 1 ? "#{item.name} × #{quantity}" : item.name

    def name_of(account) = account && (account.name.presence || account.email)
  end
end
