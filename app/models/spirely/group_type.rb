module Spirely
  # A PCO Groups "group type" (e.g. "Adult Small Groups", "Kids Small
  # Groups"), synced read-only by PcoGroupsSyncJob. `audience` is
  # Spirely-only: staff mark children's group types in Settings, and every
  # group of the type inherits it.
  class GroupType < ApplicationRecord
    AUDIENCES = %w[adults children].freeze

    belongs_to :church
    has_many :groups, class_name: "Spirely::Group", dependent: :nullify

    validates :pco_group_type_id, presence: true, uniqueness: { scope: :church_id }
    validates :name, presence: true
    validates :audience, inclusion: { in: AUDIENCES }

    scope :current, -> { where(removed_at: nil) }
  end
end
