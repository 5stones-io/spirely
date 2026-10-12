class CustomDomain < ApplicationRecord
  belongs_to :church

  # Module-scoped domains (5ST-12): an optional logo for a domain with its
  # own branding (display_name set). See Church#active_modules/#brand_name.
  has_one_attached :logo

  validates :hostname, presence: true, uniqueness: true
  validates :logo_shape, inclusion: { in: -> (_) { Church::LOGO_SHAPES } }, allow_nil: true
  validate :modules_known

  before_validation :generate_verification_token, on: :create

  def verified?
    verified_at.present?
  end

  def verify!
    update!(verified_at: Time.current)
  end

  # nil/empty modules = no restriction: the domain shows everything the
  # church has on.
  def restricted? = modules.present?

  def serves_module?(name) = !restricted? || modules.include?(name.to_s)

  # A domain with its own display_name has its own branding — its own logo
  # (or the initial-letter mark), never the church's.
  def own_branding? = display_name.present?

  private

  def modules_known
    unknown = Array(modules) - Church::KNOWN_MODULES
    errors.add(:modules, "include unknown modules: #{unknown.join(', ')}") if unknown.any?
  end

  def generate_verification_token
    self.verification_token ||= SecureRandom.hex(16)
  end
end
