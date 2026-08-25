class CustomDomain < ApplicationRecord
  belongs_to :church

  validates :hostname, presence: true, uniqueness: true

  before_validation :generate_verification_token, on: :create

  def verified?
    verified_at.present?
  end

  def verify!
    update!(verified_at: Time.current)
  end

  private

  def generate_verification_token
    self.verification_token ||= SecureRandom.hex(16)
  end
end
