module Spirely
  class Guardian < ApplicationRecord
    RELATIONSHIPS = %w[Mother Father Stepmother Stepfather Grandparent Guardian Other].freeze

    belongs_to :church
    belongs_to :family
    belongs_to :account, optional: true
    has_many :invitations, class_name: "Spirely::Invitation", dependent: :destroy

    before_validation :inherit_church_from_family

    validates :first_name,   presence: true
    validates :relationship, inclusion: { in: RELATIONSHIPS }, allow_blank: true
    # Multi-account family access: each guardian can independently claim
    # their own login (see Invitation#accept!) — same one-account-per-
    # church constraint Family#account_id already has, just per-guardian
    # instead of per-family, so two different families can't collide but
    # a guardian can't double-claim either.
    validates :account_id, uniqueness: { scope: :church_id }, allow_nil: true

    # Same "Linked Dual-Role Records" join Family#person already uses —
    # a guardian who's also a volunteer (real case: a second parent with
    # real PCO Check-Ins volunteer history) needs their *own* identity
    # resolved, not the family's primary contact's. See
    # BaseController#current_person's comment for why this matters:
    # without it, a signed-in guardian's volunteer/role detection was
    # silently checking the wrong person's data entirely.
    def person
      return nil if pco_person_id.blank?
      church.people.find_by(pco_person_id: pco_person_id)
    end

    private

    def inherit_church_from_family
      self.church_id ||= family&.church_id
    end
  end
end
