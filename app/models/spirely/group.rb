module Spirely
  # A PCO Groups group, synced read-only by PcoGroupsSyncJob. Core data
  # shared by any module that uses groups (Small Groups today, Kids
  # Ministry's children's groups later).
  class Group < ApplicationRecord
    belongs_to :church
    belongs_to :group_type, class_name: "Spirely::GroupType", optional: true
    has_many :memberships, class_name: "Spirely::GroupMembership", dependent: :destroy
    has_many :events, class_name: "Spirely::GroupEvent", dependent: :destroy
    has_many :applications, class_name: "Spirely::GroupApplication", dependent: :destroy
    has_many :schedule_assignments, class_name: "Spirely::GroupScheduleAssignment", dependent: :destroy

    validate :schedule_jobs_are_known
    validates :cadence_weekday, inclusion: { in: 0..6 }, allow_nil: true
    validates :cadence_interval_weeks, numericality: { only_integer: true, in: 1..4 }

    validates :pco_group_id, presence: true, uniqueness: { scope: :church_id }
    validates :name, presence: true

    # Still in PCO and not archived there.
    scope :active, -> { where(removed_at: nil, archived_at: nil) }

    def audience
      group_type&.audience || "adults"
    end

    def children?
      audience == "children"
    end

    # Jobs this group schedules, "lead" always first and always on.
    def jobs
      ["lead"] + (Array(schedule_jobs) & Spirely::GroupScheduleAssignment::HOSTING_JOBS)
    end

    def current_leaders
      memberships.current.leaders.includes(:person).map(&:person)
    end

    # The leader who can schedule this group from My Groups: whoever staff
    # marked, or the only leader when there's just one.
    def head_leader
      marked = memberships.current.leaders.find_by(head_leader: true)&.person
      return marked if marked
      leaders = current_leaders
      leaders.one? ? leaders.first : nil
    end

    # Who can be put in a job: leaders lead; any current member (leaders
    # included) can host or bring refreshments.
    def eligible_people(job)
      scope = memberships.current.includes(:person)
      scope = scope.leaders if job == "lead"
      scope.map(&:person).sort_by { |p| p.full_name.downcase }
    end

    # Upcoming meeting dates within `weeks`, as { date => GroupEvent or nil }.
    # Planning Center events win; a group with none upcoming falls back to
    # its Spirely-side repeat (cadence_weekday every cadence_interval_weeks).
    def meeting_dates(weeks: 4, today: Spirely::ChurchTime.today(church))
      zone   = Spirely::ChurchTime.zone(church)
      range  = today..(today + weeks * 7 - 1)
      events = self.events.held.where(starts_at: zone.parse(range.first.to_s).beginning_of_day..zone.parse(range.last.to_s).end_of_day)
                   .order(:starts_at).to_a
      if events.any?
        return events.each_with_object({}) { |e, h| h[e.starts_at.in_time_zone(zone).to_date] ||= e }
      end
      return {} if cadence_weekday.nil?

      anchor = cadence_anchor_on || range.first
      first  = range.first + ((cadence_weekday - range.first.wday) % 7)
      # Keep every-N-weeks repeats aligned to the anchor date.
      first += 7 until ((first - anchor).to_i / 7) % cadence_interval_weeks == 0 || first > range.last
      dates = []
      d = first
      while d <= range.last
        dates << d
        d += 7 * cadence_interval_weeks
      end
      dates.index_with { nil }
    end

    private

    def schedule_jobs_are_known
      unknown = Array(schedule_jobs) - Spirely::GroupScheduleAssignment::JOBS.keys
      errors.add(:schedule_jobs, "contains unknown job(s): #{unknown.join(', ')}") if unknown.any?
    end
  end
end
