module Spirely
  # Every change to a group's weekly schedule (Small Groups module, 5ST-55)
  # goes through here, whoever makes it — staff, the head leader, or
  # someone signing themselves up — so the rules live in one place:
  # - only the group's leaders can lead; any current member can host or
  #   bring refreshments
  # - only dates the group actually meets (GroupSchedule#meeting_dates)
  # - a request (staff / head leader) goes out by email and SMS and waits
  #   for an answer; signing yourself up is confirmed straight away
  # - a decline keeps the person's name (so staff see who said no) but the
  #   slot counts as open again, and the head leader / staff are told
  class GroupSchedule
    class Error < StandardError; end

    WEEKS = 4
    MAX_WEEKS = 10

    def initialize(group, weeks: WEEKS)
      @group = group
      @weeks = weeks.to_i.clamp(1, MAX_WEEKS)
    end

    # [{ meets_on:, event:, slots: { job => assignment-or-unsaved-open } }]
    def meetings
      dates = @group.meeting_dates(weeks: @weeks)
      saved = @group.schedule_assignments.where(meets_on: dates.keys).includes(:person).index_by { |a| [a.meets_on, a.job] }
      dates.map do |date, event|
        slots = @group.jobs.index_with do |job|
          saved[[date, job]] || @group.schedule_assignments.new(church: @group.church, meets_on: date, job: job, status: "open")
        end
        { meets_on: date, event: event, slots: slots }
      end
    end

    def assign!(meets_on:, job:, person:, by_account:, source:)
      validate!(meets_on, job, person)
      slot = slot_for(meets_on, job)
      return slot if slot.person_id == person.id && slot.status.in?(%w[pending accepted])

      slot.update!(person: person, status: "pending", source: source, assigned_by_account: by_account,
                   responded_at: nil, notified_at: nil, notify_channels: [])
      Spirely::ScheduleNotifier.request(slot, slot.issue_token!)
      slot
    end

    def sign_up!(meets_on:, job:, person:)
      validate!(meets_on, job, person)
      slot = slot_for(meets_on, job)
      raise Error, "Someone already has this spot." unless slot.new_record? || slot.fillable? || slot.person_id == person.id

      slot.update!(person: person, status: "accepted", source: "self", assigned_by_account: nil,
                   responded_at: Time.current, token_digest: nil, token_expires_at: nil)
      slot
    end

    def unassign!(meets_on:, job:)
      slot = @group.schedule_assignments.find_by(meets_on: meets_on, job: job)
      slot&.update!(person: nil, status: "open", source: nil, assigned_by_account: nil, responded_at: nil,
                    token_digest: nil, token_expires_at: nil, notified_at: nil, notify_channels: [])
      slot
    end

    def resend!(slot)
      raise Error, "There's no one to ask for this spot yet." unless slot.person && slot.status == "pending"
      Spirely::ScheduleNotifier.request(slot, slot.issue_token!)
      slot
    end

    # Accept or decline. Changing your mind is allowed until the meeting
    # day ends; repeating the same answer changes nothing.
    def self.respond!(slot, choice)
      status = { "accept" => "accepted", "decline" => "declined" }.fetch(choice.to_s) { raise Error, "Choose accept or decline." }
      return slot if slot.status == status

      slot.update!(status: status, responded_at: Time.current)
      Spirely::ScheduleNotifier.declined(slot) if status == "declined"
      slot
    end

    private

    def validate!(meets_on, job, person)
      raise Error, "This group doesn't schedule that job." unless @group.jobs.include?(job)
      raise Error, "The group doesn't meet that day." unless @group.meeting_dates(weeks: MAX_WEEKS).key?(meets_on)
      return if @group.eligible_people(job).include?(person)

      raise Error, job == "lead" ? "Only this group's leaders can lead." : "Only members of this group can do that."
    end

    def slot_for(meets_on, job)
      event = @group.meeting_dates(weeks: MAX_WEEKS)[meets_on]
      @group.schedule_assignments.find_or_initialize_by(meets_on: meets_on, job: job) do |s|
        s.church = @group.church
      end.tap { |s| s.group_event = event }
    end
  end
end
