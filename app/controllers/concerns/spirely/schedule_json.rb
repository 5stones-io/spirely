module Spirely
  # JSON for the weekly group schedule (Small Groups, 5ST-55), shared by
  # the staff grid, My Groups and the overview.
  module ScheduleJson
    extend ActiveSupport::Concern

    private

    def person_ref(person) = person && { id: person.id, name: person.full_name }

    def slot_json(slot)
      {
        id:              slot.id,
        job:             slot.job,
        job_label:       slot.job_label,
        status:          slot.status,
        person:          person_ref(slot.person),
        source:          slot.source,
        notified_at:     slot.notified_at,
        notify_channels: slot.notify_channels,
        responded_at:    slot.responded_at,
      }
    end

    def meeting_json(group, meeting)
      zone = Spirely::ChurchTime.zone(group.church)
      {
        meets_on: meeting[:meets_on],
        label:    meeting[:meets_on].strftime("%a %b %-d"),
        time:     meeting[:event]&.starts_at&.in_time_zone(zone)&.strftime("%-l:%M%P"),
        slots:    meeting[:slots].values.map { |s| slot_json(s) },
      }
    end

    # A meeting is covered when its lead — and host, if the group uses a
    # host — has said yes. Open/declined slots are what still needs filling.
    def schedule_summary(groups_meetings)
      meetings = groups_meetings.flat_map { |_g, ms| ms }
      slots = meetings.flat_map { |m| m[:slots].values }
      covered = meetings.count do |m|
        %w[lead host_home].all? { |job| !m[:slots].key?(job) || m[:slots][job].status == "accepted" }
      end
      {
        meetings:     meetings.size,
        covered:      covered,
        coverage_pct: meetings.empty? ? nil : (covered * 100.0 / meetings.size).round,
        open_slots:   slots.count(&:fillable?),
        declined:     slots.count { |s| s.status == "declined" },
        pending:      slots.count { |s| s.status == "pending" },
      }
    end

    def eligible_json(group)
      { lead: group.eligible_people("lead").map { |p| person_ref(p) },
        hosting: group.eligible_people("host_home").map { |p| person_ref(p) } }
    end
  end
end
