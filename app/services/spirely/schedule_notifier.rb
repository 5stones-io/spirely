module Spirely
  # Sends schedule requests and decline notices (Small Groups, 5ST-55).
  # Same delivery rules as InviteSender: email whenever there's an
  # address; SMS only when the church's Twilio is verified and the person
  # has a phone. The request link goes to a page where they confirm —
  # tapping it never answers on its own, so email link scanners can't.
  class ScheduleNotifier
    def self.response_url(church, token)
      "https://#{church.primary_hostname}/schedule/r/#{token}"
    end

    def self.request(slot, token)
      person  = slot.person
      church  = slot.church
      url     = response_url(church, token)
      sent    = []

      if person.email.present?
        Spirely::ScheduleMailer.schedule_request(slot, url).deliver_later
        sent << "email"
      end

      integration = church.church_integration
      if integration&.twilio_verified? && person.phone.present?
        begin
          Spirely::Sms.new(integration).send(
            to: person.phone,
            body: "#{church.name}: can you #{slot.job_verb} #{slot.group.name} on #{slot.meets_on.strftime('%a %b %-d')}? Answer here: #{url}"
          )
          sent << "sms"
        rescue Spirely::SmsError, Spirely::ConfigError => e
          Rails.logger.error("[Spirely] Schedule SMS failed for assignment #{slot.id}: #{e.message}")
        end
      end

      slot.update!(notified_at: Time.current, notify_channels: sent)
      sent
    end

    # Tells the head leader (or, with none, the church's admins) that
    # someone said no, so the spot can be filled.
    def self.declined(slot)
      head = slot.group.head_leader
      recipients =
        if head&.email.present? && head != slot.person
          [head.email]
        else
          Membership.where(church: slot.church, role: %w[admin owner]).includes(:account).map { |m| m.account.email }
        end
      recipients.compact.uniq.each { |email| Spirely::ScheduleMailer.declined(slot, email).deliver_later }
    end
  end
end
