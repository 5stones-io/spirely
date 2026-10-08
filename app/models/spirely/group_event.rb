module Spirely
  # One group meeting (a PCO Groups event). Past ones carry attendance;
  # upcoming ones are the dates leader scheduling works from.
  class GroupEvent < ApplicationRecord
    belongs_to :church
    belongs_to :group, class_name: "Spirely::Group"
    has_many :attendances, class_name: "Spirely::GroupAttendance", dependent: :destroy

    validates :pco_event_id, presence: true, uniqueness: { scope: :church_id }
    validates :starts_at, presence: true

    # Still in PCO and not canceled — a real meeting.
    scope :held, -> { where(removed_at: nil, canceled: false) }
    scope :past, -> { where("starts_at < ?", Time.current) }
    scope :upcoming, -> { where("starts_at >= ?", Time.current) }
  end
end
