module Spirely
  # JSON shapes shared by the staff Kudos screens and My Points (5ST-60).
  module KudosJson
    extend ActiveSupport::Concern

    private

    def kudos = @kudos ||= Spirely::Kudos.new(Current.church)

    def points_entry_json(entry, with_person: false)
      json = {
        id: entry.id, points: entry.points, note: entry.note, source: entry.source,
        occurred_on: entry.occurred_on, by: entry.awarded_by_name, created_at: entry.created_at,
      }
      json[:balance_after] = entry.balance_after.to_i if entry.has_attribute?(:balance_after)
      json[:person] = { pco_person_id: entry.person.pco_person_id, name: entry.person.full_name } if with_person
      # The plan, roles and times behind time served (5ST-62).
      json[:serving] = entry.details["serving"] if entry.details&.key?("serving")
      json
    end

    # A store item (5ST-63). Staff also see instructions and hidden items;
    # people see instructions only on their own orders.
    def store_item_json(item, staff: false)
      json = {
        id: item.id, name: item.name, description: item.description, points: item.points, kind: item.kind,
        audience: item.audience, per_person_limit: item.per_person_limit, remaining: item.remaining,
        image_url: store_image_url(item),
      }
      json.merge!(stock: item.stock, instructions: item.instructions, hidden: item.hidden?, position: item.position) if staff
      json
    end

    # An order line. What was delivered (instructions or codes) is only
    # included for digital items, which are delivered on redemption.
    def store_order_json(order, with_person: false)
      json = {
        id: order.id, item: { id: order.item_id, name: order.item.name, kind: order.item.kind, image_url: store_image_url(order.item) },
        quantity: order.quantity,
        points: order.points, status: order.status, channel: order.channel, placed_at: order.created_at,
        placed_by: order.placed_by_name, fulfilled_at: order.fulfilled_at, fulfilled_by: order.fulfilled_by_name,
        cancelled_at: order.cancelled_at, cancelled_by: order.cancelled_by_name,
      }
      if order.item.digital?
        json[:instructions] = order.item.instructions
        json[:codes] = order.codes.map(&:code) if order.item.kind == "code"
      end
      json[:person] = { pco_person_id: order.person.pco_person_id, name: order.person.full_name, kid: !!order.person.child } if with_person
      json
    end

    def store_image_url(item)
      item.image.attached? ? Rails.application.routes.url_helpers.rails_blob_path(item.image, only_path: true) : nil
    end
  end
end
