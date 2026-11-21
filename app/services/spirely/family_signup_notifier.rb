module Spirely
  # Emails a church's admins and owners when a new family sends the Create
  # Account form (5ST-85), one email each.
  class FamilySignupNotifier
    def self.submitted(signup)
      emails = signup.church.memberships.where(role: %w[admin owner]).joins(:account).pluck("accounts.email")
      emails.compact_blank.uniq.each { |email| Spirely::FamilySignupMailer.submitted(signup, email).deliver_later }
    end
  end
end
