module Spirely
  # One code in a digital item's pool (e.g. a coffee voucher), given to
  # the order that redeems it.
  class StoreCode < ApplicationRecord
    belongs_to :church
    belongs_to :item, class_name: "Spirely::StoreItem"
    belongs_to :order, class_name: "Spirely::StoreOrder", optional: true

    validates :code, presence: true, length: { maximum: 120 }, uniqueness: { scope: :item_id }
  end
end
