module Spirely
  # A pending request to join a group (PCO "group application"). Display
  # only in Spirely — approving or rejecting happens in Planning Center.
  # Deleted by the sync once it's no longer pending there.
  class GroupApplication < ApplicationRecord
    belongs_to :church
    belongs_to :group, class_name: "Spirely::Group"
    belongs_to :person, class_name: "Spirely::Person"

    validates :pco_application_id, presence: true, uniqueness: { scope: :church_id }
    validates :status, presence: true
  end
end
