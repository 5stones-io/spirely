module Spirely
  class Family < ApplicationRecord
    belongs_to :church
    belongs_to :account, optional: true
    has_many :children,     dependent: :destroy
    has_many :guardians,    dependent: :destroy
    has_many :invitations,  dependent: :destroy
    has_many :contact_notes, class_name: "Spirely::ContactNote", dependent: :destroy
    has_many :family_posts, class_name: "Spirely::FamilyPost", dependent: :destroy

    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
    validates :account_id, uniqueness: { scope: :church_id }, allow_nil: true

    # The Families list/stats are meant to be a CRM view of actual
    # families with kids enrolled — a guardian/contact record with no
    # children yet (e.g. a stray PCO sync artifact, or a household
    # created before any child was added) shouldn't count or appear
    # there.
    scope :with_children, -> { joins(:children).distinct }

    # "Active" here means real PCO attendance history, same sense PCO
    # itself uses — someone in the family (a child, or the primary
    # contact) has actually checked in within the window — not whether
    # they have kids on file or a claimed account (see with_children /
    # account_linked, which are separate, boolean concerns). Matched via
    # the same shared-pco_person_id bridge Child#person/Family#person
    # already use, not a real FK, since Person is synced independently.
    ATTENDANCE_ACTIVE_WINDOW = 1.year

    RECENT_ATTENDANCE_SQL = <<~SQL.squish
      EXISTS (
        SELECT 1 FROM spirely_people people
        INNER JOIN spirely_attendances attendances ON attendances.person_id = people.id
        WHERE people.church_id = spirely_families.church_id
          AND attendances.checked_in_at >= :since
          AND (
            people.pco_person_id = spirely_families.pco_person_id
            OR EXISTS (
              SELECT 1 FROM spirely_children children
              WHERE children.family_id = spirely_families.id
                AND children.pco_person_id = people.pco_person_id
            )
          )
      )
    SQL

    scope :attendance_active,   ->(since = ATTENDANCE_ACTIVE_WINDOW.ago) { where(RECENT_ATTENDANCE_SQL, since: since) }
    scope :attendance_inactive, ->(since = ATTENDANCE_ACTIVE_WINDOW.ago) { where.not(RECENT_ATTENDANCE_SQL, since: since) }

    # Matches on the family's own fields *and* its Guardians/Children —
    # found needed when Chad couldn't find "Becca Nelson" on the Families
    # page at all: she's a real Guardian on the Nelson family (a second
    # adult in the household, per PcoInboundPeopleSyncJob's multi-adult
    # sync), but the family's own searchable fields only ever hold its
    # *primary* contact ("Adam Nelson") — a guardian's name never
    # appeared anywhere search could reach before this.
    SEARCH_SQL = <<~SQL.squish
      spirely_families.family_name ILIKE :q
      OR spirely_families.primary_contact_first_name ILIKE :q
      OR spirely_families.primary_contact_last_name ILIKE :q
      OR spirely_families.email ILIKE :q
      OR spirely_families.phone ILIKE :q
      OR EXISTS (
        SELECT 1 FROM spirely_guardians g
        WHERE g.family_id = spirely_families.id
          AND (g.first_name ILIKE :q OR g.last_name ILIKE :q)
      )
      OR EXISTS (
        SELECT 1 FROM spirely_children c
        WHERE c.family_id = spirely_families.id
          AND (c.first_name ILIKE :q OR c.last_name ILIKE :q)
      )
    SQL

    scope :search, ->(query) { where(SEARCH_SQL, q: "%#{query.to_s.strip}%") }

    after_commit :enqueue_outbound_profile_sync, on: :update, if: :profile_changed?

    def primary_contact_name
      "#{primary_contact_first_name} #{primary_contact_last_name}".strip
    end

    def primary_contact_name=(full_name)
      parts = full_name.to_s.strip.split(" ", 2)
      self.primary_contact_first_name = parts[0].to_s
      self.primary_contact_last_name  = parts[1].to_s
    end

    # The "Linked Dual-Role Records" gap (a parent who's also a volunteer)
    # — same join-by-shared-pco_person_id approach as Child#person, using
    # the primary contact's own PCO identity (PcoInboundPeopleSyncJob
    # already stamps this on the Family, not a Guardian — Guardian rows
    # are staff-entered and never PCO-synced at all, so they're not a
    # reliable join key). Nil unless the family has actually synced from
    # PCO and the same person independently has a Spirely::Person record
    # (e.g. from the Volunteers pipeline or their own Check-Ins history).
    def person
      return nil if pco_person_id.blank?
      church.people.find_by(pco_person_id: pco_person_id)
    end

    private

    def profile_changed?
      previous_changes.keys.intersect?(%w[
        family_name primary_contact_first_name primary_contact_last_name email phone
      ])
    end

    def enqueue_outbound_profile_sync
      return unless pco_sync_enabled?
      return unless church.sync_setting&.outbound_people_sync?

      Spirely::PcoOutboundProfileSyncJob.perform_later(id)
    end
  end
end
