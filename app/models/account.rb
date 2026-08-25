class Account < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :churches, through: :memberships
  has_one  :family, class_name: "Spirely::Family", foreign_key: :account_id, dependent: :nullify
  has_many :guardians, class_name: "Spirely::Guardian", foreign_key: :account_id, dependent: :nullify

  before_validation :normalize_email

  private

  # Every account-by-login lookup (RodauthMain#account_from_login) does a
  # find_or_create_by! with no case normalization on either side — a real
  # way for two different-case spellings of the same email to silently
  # resolve to two different Account rows (one Membership living on one
  # row, a later login creating/matching a second, membership-less row).
  # This callback keeps every *saved* row canonical; the lookup call site
  # still downcases before searching too, since find_or_create_by!'s own
  # find_by happens before this ever runs.
  def normalize_email
    self.email = email.to_s.strip.downcase if email.present?
  end
end
