module Spirely
  # Something in a church's Kudos store (5ST-63). Three kinds:
  #   physical      handed over at pickup or checkout; stock is optional
  #   instructions  digital, shows `instructions` once redeemed
  #   code          digital, hands out one code from its pool per item
  # Images live under a per-church key prefix, like incident photos.
  class StoreItem < ApplicationRecord
    KINDS = %w[physical instructions code].freeze
    AUDIENCES = %w[everyone adults kids].freeze
    MAX_IMAGE_SIZE = 5.megabytes

    belongs_to :church
    has_many :orders, class_name: "Spirely::StoreOrder", foreign_key: :item_id, dependent: :restrict_with_error
    has_many :codes, class_name: "Spirely::StoreCode", foreign_key: :item_id, dependent: :delete_all
    has_one_attached :image

    validates :name, presence: true, length: { maximum: 80 }
    validates :description, length: { maximum: 500 }
    validates :points, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: Kudos::MAX_POINTS }
    validates :kind, inclusion: { in: KINDS }
    validates :audience, inclusion: { in: AUDIENCES }
    validates :stock, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    validates :per_person_limit, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validates :instructions, presence: true, if: -> { kind == "instructions" }
    validate :stock_only_for_physical

    scope :visible, -> { where(hidden_at: nil) }
    scope :ordered, -> { order(:position, :id) }

    def digital? = kind != "physical"
    def hidden? = hidden_at.present?

    # How many can still be had: tracked stock, or codes left in the pool.
    # nil means no limit.
    def remaining
      return codes.where(order_id: nil).count if kind == "code"
      stock
    end

    def for?(kid:) = audience == "everyone" || (audience == "kids") == kid

    def attach_image(file)
      raise Kudos::Error, "Pick a JPG, PNG, GIF or WebP image." unless file.content_type.to_s.start_with?("image/")
      raise Kudos::Error, "That image is over 5 MB." if file.size > MAX_IMAGE_SIZE

      blob = ActiveStorage::Blob.create_and_upload!(
        io: file, filename: file.original_filename, content_type: file.content_type,
        key: "church-#{church_id}/kudos-store/#{ActiveStorage::Blob.generate_unique_secure_token}",
      )
      image.attach(blob)
    end

    private

    def stock_only_for_physical
      errors.add(:stock, "only applies to physical items") if stock && digital?
    end
  end
end
