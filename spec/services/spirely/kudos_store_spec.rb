require "rails_helper"

# Kudos phase 4 (5ST-63): the store.
RSpec.describe Spirely::KudosStore do
  let(:church) { create(:church, enabled_modules: ["kudos"]) }
  let(:store)  { described_class.new(church) }
  let(:kudos)  { Spirely::Kudos.new(church) }
  let(:staff)  { create(:account, first_name: "Jenna", last_name: "Park") }
  let!(:sarah) { create(:spirely_person, church: church, first_name: "Sarah", pco_person_id: "sarah") }
  let!(:emma)  { create(:spirely_person, church: church, first_name: "Emma", pco_person_id: "emma", child: true) }

  def item(**attrs)
    church.store_items.create!(name: "T-shirt", points: 100, **attrs)
  end

  def give(person, points) = kudos.award!(pco_person_id: person.pco_person_id, points: points, note: "Thanks", by_account: staff)
  def balance(person) = kudos.totals(person)[:balance]

  describe "#redeem!" do
    it "takes the points straight away and queues a physical item for pickup" do
      give(sarah, 250)
      shirt = item(stock: 3)

      order = store.redeem!(pco_person_id: "sarah", item_id: shirt.id, quantity: 2)

      expect(order).to have_attributes(status: "pending", channel: "online", quantity: 2, points: 200)
      expect(balance(sarah)).to eq(50)
      expect(shirt.reload.stock).to eq(1)
      expect(sarah.points_entries.newest_first.first)
        .to have_attributes(points: -200, source: "redemption", source_id: order.id, note: "T-shirt × 2")
    end

    it "won't let anyone go below zero" do
      give(sarah, 50)
      expect { store.redeem!(pco_person_id: "sarah", item_id: item.id) }
        .to raise_error(Spirely::Kudos::Error, "Sarah has 50 points — that's 100.")
      expect(church.store_orders).to be_empty
      expect(balance(sarah)).to eq(50)
    end

    it "says when an item is sold out or has too few left" do
      give(sarah, 1_000)
      shirt = item(stock: 1)
      expect { store.redeem!(pco_person_id: "sarah", item_id: shirt.id, quantity: 2) }
        .to raise_error(Spirely::Kudos::Error, "Only 1 T-shirt left.")
      store.redeem!(pco_person_id: "sarah", item_id: shirt.id)
      expect { store.redeem!(pco_person_id: "sarah", item_id: shirt.id) }
        .to raise_error(Spirely::Kudos::Error, "T-shirt is sold out.")
    end

    it "keeps to the per-person limit, not counting cancelled orders" do
      give(sarah, 1_000)
      shirt = item(per_person_limit: 1)
      order = store.redeem!(pco_person_id: "sarah", item_id: shirt.id)
      expect { store.redeem!(pco_person_id: "sarah", item_id: shirt.id) }
        .to raise_error(Spirely::Kudos::Error, "Sarah already has the most T-shirt allowed.")

      store.cancel!(order, by_account: staff)
      expect { store.redeem!(pco_person_id: "sarah", item_id: shirt.id) }.not_to raise_error
    end

    it "only sells items for the person's audience, and not hidden ones" do
      give(emma, 500)
      give(sarah, 500)
      expect { store.redeem!(pco_person_id: "sarah", item_id: item(audience: "kids").id) }
        .to raise_error(Spirely::Kudos::Error, "T-shirt is just for kids.")
      expect { store.redeem!(pco_person_id: "emma", item_id: item(hidden_at: Time.current).id) }
        .to raise_error(Spirely::Kudos::Error, "T-shirt isn't in the store right now.")
      expect(store.items_for(kid: true).map(&:audience)).to eq(["kids"])
    end

    it "delivers a code item at once, one code per item" do
      give(sarah, 500)
      coffee = item(name: "Coffee", points: 50, kind: "code")
      expect(store.add_codes!(coffee, "AAA\nBBB\n\nAAA\nCCC")).to eq(3)

      order = store.redeem!(pco_person_id: "sarah", item_id: coffee.id, quantity: 2)

      expect(order.status).to eq("fulfilled")
      expect(order.codes.order(:id).pluck(:code)).to eq(%w[AAA BBB])
      expect(coffee.remaining).to eq(1)
      expect { store.redeem!(pco_person_id: "sarah", item_id: coffee.id, quantity: 2) }
        .to raise_error(Spirely::Kudos::Error, "Only 1 Coffee left.")
    end

    it "delivers an instructions item at once" do
      give(sarah, 500)
      perk = item(name: "Front-row seat", kind: "instructions", instructions: "Show this at the door.")
      expect(store.redeem!(pco_person_id: "sarah", item_id: perk.id).status).to eq("fulfilled")
    end
  end

  describe "#checkout!" do
    it "hands everything over on the spot, checking the total against the balance" do
      give(emma, 150)
      shirt = item(stock: 5)
      sticker = item(name: "Sticker", points: 25)
      expect { store.checkout!(pco_person_id: "emma", lines: [{ item_id: shirt.id, quantity: 1 }, { item_id: sticker.id, quantity: 3 }], by_account: staff) }
        .to raise_error(Spirely::Kudos::Error, "Emma has 150 points — that's 175.")

      orders = store.checkout!(pco_person_id: "emma", lines: [{ item_id: shirt.id, quantity: 1 }, { item_id: sticker.id, quantity: 2 }],
                               by_account: staff)

      expect(orders.map { |o| [o.status, o.channel, o.fulfilled_by_name] }).to all(eq(["fulfilled", "checkout", "Jenna Park"]))
      expect(balance(emma)).to eq(0)
    end
  end

  describe "#cancel! and #fulfill!" do
    it "refunds the points and puts the stock back, once" do
      give(sarah, 300)
      shirt = item(stock: 2)
      order = store.redeem!(pco_person_id: "sarah", item_id: shirt.id, quantity: 2)

      store.cancel!(order, by_account: staff)

      expect(order.reload).to have_attributes(status: "cancelled", cancelled_by_name: "Jenna Park")
      expect(order.refund_entry).to have_attributes(points: 200, source: "refund", note: "Refund · T-shirt × 2")
      expect(balance(sarah)).to eq(300)
      expect(shirt.reload.stock).to eq(2)
      expect { store.cancel!(order, by_account: staff) }.to raise_error(Spirely::Kudos::Error, "That order was already cancelled.")
    end

    it "marks a pickup handed over, and then it can't be cancelled" do
      give(sarah, 300)
      order = store.redeem!(pco_person_id: "sarah", item_id: item.id)

      store.fulfill!(order, by_account: staff)

      expect(order.reload).to have_attributes(status: "fulfilled", fulfilled_by_name: "Jenna Park")
      expect { store.cancel!(order, by_account: staff) }.to raise_error(Spirely::Kudos::Error, "That order was already fulfilled.")
    end
  end

  # Real concurrent transactions need their own connections, so these run
  # outside the per-example transaction and clean up after themselves.
  describe "under concurrent redemptions", :concurrency do
    self.use_transactional_tests = false

    after do
      church.store_codes.delete_all
      church.store_orders.delete_all
      church.points_entries.delete_all
      church.store_items.delete_all
      Spirely::KudosSetting.where(church: church).delete_all
      church.people.delete_all
      Account.where(id: staff.id).delete_all
      Church.where(id: church.id).delete_all
    end

    def race(n)
      threads = n.times.map do |i|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection { yield(i); :ok }
        rescue Spirely::Kudos::Error => e
          e.message
        end
      end
      threads.map(&:value)
    end

    it "sells the last item once" do
      give(sarah, 1_000)
      give(emma, 1_000)
      shirt = item(stock: 1)

      results = race(2) { |i| store.redeem!(pco_person_id: i.zero? ? "sarah" : "emma", item_id: shirt.id) }

      expect(results).to contain_exactly(:ok, "T-shirt is sold out.")
      expect(shirt.reload.stock).to eq(0)
    end

    it "never spends the same points twice" do
      give(sarah, 100)
      shirt = item

      results = race(3) { store.redeem!(pco_person_id: "sarah", item_id: shirt.id) }

      expect(results.count(:ok)).to eq(1)
      expect(balance(sarah)).to eq(0)
    end

    it "hands each code to one order" do
      give(sarah, 1_000)
      coffee = item(name: "Coffee", points: 10, kind: "code")
      store.add_codes!(coffee, "AAA\nBBB")

      results = race(3) { store.redeem!(pco_person_id: "sarah", item_id: coffee.id) }

      expect(results.count(:ok)).to eq(2)
      expect(coffee.codes.where.not(order_id: nil).distinct.count(:order_id)).to eq(2)
    end
  end
end
