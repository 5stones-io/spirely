module Spirely
  # One line of a Kudos store order (5ST-63): an item, how many, and the
  # points it cost. Online physical orders wait in the pickup queue
  # (pending) until staff hand them over; checkout and digital orders are
  # fulfilled straight away. Cancelling refunds the points.
  class StoreOrder < ApplicationRecord
    STATUSES = %w[pending fulfilled cancelled].freeze
    CHANNELS = %w[online checkout].freeze

    belongs_to :church
    belongs_to :person, class_name: "Spirely::Person"
    belongs_to :item, class_name: "Spirely::StoreItem"
    belongs_to :placed_by_account, class_name: "Account", optional: true
    belongs_to :refund_entry, class_name: "Spirely::PointsEntry", optional: true
    has_many :codes, class_name: "Spirely::StoreCode", foreign_key: :order_id, dependent: :nullify
    has_one :redemption_entry, -> { where(source: "redemption") }, class_name: "Spirely::PointsEntry", as: :source

    validates :status, inclusion: { in: STATUSES }
    validates :channel, inclusion: { in: CHANNELS }
    validates :quantity, numericality: { only_integer: true, greater_than: 0 }
    validates :points, numericality: { only_integer: true, greater_than: 0 }

    scope :pending, -> { where(status: "pending") }
    scope :not_cancelled, -> { where.not(status: "cancelled") }
    scope :newest_first, -> { order(created_at: :desc, id: :desc) }

    def pending? = status == "pending"
  end
end
