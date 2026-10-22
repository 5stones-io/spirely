module Spirely
  # A Kudos promo code (5ST-61): staff create one worth some points, and
  # people claim it from My Points. Each person can claim a code once —
  # a claim is a PointsEntry whose source is the code. Codes are stored
  # upper-case so claiming is case-insensitive.
  class PromoCode < ApplicationRecord
    belongs_to :church
    belongs_to :created_by_account, class_name: "Account", optional: true
    has_many :claims, -> { where(source: "promo_code") }, class_name: "Spirely::PointsEntry",
             as: :source, dependent: :restrict_with_error

    before_validation { self.code = self.class.normalize(code) }

    validates :code, presence: true, uniqueness: { scope: :church_id, message: "is already used by another code" },
                     format: { with: /\A[A-Z0-9-]{3,24}\z/, message: "can only use letters, numbers and dashes (3–24)", allow_blank: true }
    validates :label, presence: true, length: { maximum: 80 }
    validates :points, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: Kudos::MAX_POINTS }
    validates :max_uses, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

    def self.normalize(code) = code.to_s.strip.upcase.presence

    # A short code that's easy to read aloud: no 0/O or 1/I.
    def self.generate_code
      Array.new(6) { "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars.sample }.join
    end

    def turned_off? = turned_off_at.present?

    def expired?(today) = expires_on.present? && expires_on < today

    # "active", "off", "expired" or "used_up". uses is passed in so a list
    # can count every code's claims in one query.
    def status(today:, uses:)
      if turned_off? then "off"
      elsif expired?(today) then "expired"
      elsif max_uses && uses >= max_uses then "used_up"
      else "active"
      end
    end
  end
end
