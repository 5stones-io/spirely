module Spirely
  # A PCO Services service type (e.g. "Sunday Services"), synced read-only
  # by PcoServicesSyncJob for Kudos time served (5ST-62).
  class ServiceType < ApplicationRecord
    belongs_to :church
    has_many :plans, class_name: "Spirely::ServicePlan", dependent: :destroy

    validates :pco_service_type_id, presence: true, uniqueness: { scope: :church_id }
    validates :name, presence: true

    scope :current, -> { where(removed_at: nil) }
  end
end
