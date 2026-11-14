module Spirely
  # Emails a church's admins and owners when feedback comes in (5ST-80),
  # one email each, leaving out the sender.
  class FeedbackNotifier
    def self.inbox_url(feedback)
      "https://#{feedback.church.primary_hostname}/feedback-inbox?id=#{feedback.id}"
    end

    def self.submitted(feedback)
      emails = feedback.church.memberships.where(role: %w[admin owner])
                       .where.not(account_id: feedback.account_id)
                       .joins(:account).pluck("accounts.email")
      emails.compact_blank.uniq.each { |email| Spirely::FeedbackMailer.submitted(feedback, email).deliver_later }
    end
  end
end
