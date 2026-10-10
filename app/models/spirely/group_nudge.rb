module Spirely
  # An attendance follow-up (Small Groups, 5ST-53): someone who used to come
  # to a group or class regularly and has missed the last couple of
  # meetings. Created and refreshed by GroupNudgeSyncJob, never closed
  # automatically — a person closes it by logging what happened.
  class GroupNudge < ApplicationRecord
    RESOLUTIONS = {
      "contacted" => "Contacted",
      "returned"  => "Came back",
      "dismissed" => "Dismissed",
    }.freeze

    belongs_to :church
    belongs_to :group, class_name: "Spirely::Group"
    belongs_to :person, class_name: "Spirely::Person"
    belongs_to :owner_person, class_name: "Spirely::Person", optional: true
    belongs_to :resolved_by_account, class_name: "::Account", optional: true
    has_many :notes, -> { order(created_at: :desc, id: :desc) }, class_name: "Spirely::GroupNudgeNote", dependent: :destroy

    validates :resolution, inclusion: { in: RESOLUTIONS.keys }, allow_nil: true

    scope :open, -> { where(resolved_at: nil) }
    scope :resolved, -> { where.not(resolved_at: nil) }

    def open? = resolved_at.nil?

    # When they've been to the group since the meetings this follow-up is
    # based on, the date — so nobody calls someone who's already back.
    # Counted from the last missed meeting, not created_at, since a sync
    # can run a day or more after a meeting.
    def came_back_on
      last = Array(metrics["meetings"]).last&.dig("date")
      since = last ? Spirely::ChurchTime.zone(church).parse(last).end_of_day : created_at
      group.events.held.where("starts_at > ?", since)
           .joins(:attendances).where(spirely_group_attendances: { person_id: person_id, attended: true })
           .minimum(:starts_at)
    end

    # Adds a history entry; an outcome closes the follow-up.
    def log!(account:, body: nil, outcome: nil)
      raise ArgumentError, "Unknown outcome" if outcome && !RESOLUTIONS.key?(outcome)
      raise ArgumentError, "Write a note or choose what happened" if body.blank? && outcome.nil?

      transaction do
        notes.create!(church: church, author_account: account, author_name: account&.name || account&.email,
                      body: body.presence, outcome: outcome)
        update!(resolved_at: Time.current, resolution: outcome, resolved_by_account: account) if outcome && open?
      end
      self
    end
  end
end
