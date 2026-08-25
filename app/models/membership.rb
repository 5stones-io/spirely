class Membership < ApplicationRecord
  ROLES = %w[family admin owner].freeze

  belongs_to :account
  belongs_to :church

  validates :role, inclusion: { in: ROLES }
  validates :account_id, uniqueness: { scope: :church_id }

  def admin_or_owner?
    role.in?(%w[admin owner])
  end
end
