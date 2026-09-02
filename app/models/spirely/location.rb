module Spirely
  # A PCO Check-Ins "Location" (what church staff call a room — Nursery,
  # K-2 Room, etc), synced read-only from PCO by PcoAttendanceSyncJob.
  # Exists so features that scope by room (attendance, room-scoped
  # announcements) can reference a real, stable row instead of matching on
  # the denormalized location_name string PCO returns per check-in.
  class Location < ApplicationRecord
    belongs_to :church
    has_many :attendances, class_name: "Spirely::Attendance", dependent: :nullify

    validates :pco_location_id, presence: true, uniqueness: { scope: :church_id }
    validates :name, presence: true
  end
end
