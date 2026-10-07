module Spirely
  # Whether a person attended one group meeting, as submitted in PCO
  # Groups. A meeting with no rows means attendance was never taken, not
  # that nobody came.
  class GroupAttendance < ApplicationRecord
    belongs_to :church
    belongs_to :group_event, class_name: "Spirely::GroupEvent"
    belongs_to :person, class_name: "Spirely::Person"

    validates :person_id, uniqueness: { scope: :group_event_id }
  end
end
