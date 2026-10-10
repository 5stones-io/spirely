module Spirely
  class ScheduleMailer < ApplicationMailer
    # "Can you lead Moms Connect on Wed Oct 29?" — Accept / Decline buttons
    # both open the response page (/schedule/r/:token), where the person
    # confirms. Built from the Figma "email-schedule-request" frame.
    def schedule_request(slot, url)
      @slot       = slot
      @church     = slot.church
      @first_name = slot.person.first_name.presence || "there"
      @asker      = slot.assigned_by_account&.name || @church.name
      @accept_url = "#{url}?choice=accept"
      @decline_url = "#{url}?choice=decline"
      @when       = meeting_time(slot)
      mail(to: slot.person.email,
           subject: "Can you #{slot.job_verb} #{slot.group.name} on #{slot.meets_on.strftime('%a %b %-d')}?")
    end

    def declined(slot, to)
      @slot   = slot
      @church = slot.church
      @name   = slot.person&.full_name || "Someone"
      mail(to: to, subject: "#{@name} can't #{slot.job_verb} #{slot.group.name} on #{slot.meets_on.strftime('%a %b %-d')}")
    end

    private

    def meeting_time(slot)
      date = slot.meets_on.strftime("%A, %b %-d")
      return date unless slot.group_event
      "#{date} · #{slot.group_event.starts_at.in_time_zone(Spirely::ChurchTime.zone(slot.church)).strftime('%-l:%M%P')}"
    end
  end
end
