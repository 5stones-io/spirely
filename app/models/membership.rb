class Membership < ApplicationRecord
  ROLES = %w[family admin owner].freeze

  belongs_to :account
  belongs_to :church
  has_many :time_entries, class_name: "Spirely::TimeEntry", dependent: :delete_all

  validates :role, inclusion: { in: ROLES }
  validates :account_id, uniqueness: { scope: :church_id }

  def admin_or_owner?
    role.in?(%w[admin owner])
  end

  # Can use the time card: admins and owners, and members marked as staff.
  def time_card? = staff? || admin_or_owner?

  # Can run the Kudos store desk (checkout and the pickup queue): admins
  # and owners, and members marked as Kudos helpers.
  def store_desk? = kudos_helper? || admin_or_owner?
end
