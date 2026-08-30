module Spirely
  class Task < ApplicationRecord
    # Canonical Spirely status set (5ST-6) — kept deliberately small and
    # not a 1:1 mirror of any particular PCO Workflow's step sequence,
    # since that sequence varies per workflow and isn't a simple status
    # enum. Mapping this set to/from a synced PCO Workflow card's steps
    # (map_status_in/out) is future PCO-sync work, not built yet.
    STATUSES = %w[not_started in_progress blocked complete].freeze

    # 5ST-7 — small enum + interval, not full RRULE (Chad's call).
    # "every_n_days" is the only rule that uses recurrence_interval; the
    # others have a fixed cadence baked into their name.
    RECURRENCE_RULES = %w[none daily weekly biweekly monthly every_n_days].freeze
    RECURRENCE_MODES = %w[relative absolute].freeze

    belongs_to :church
    belongs_to :assignee,   class_name: "::Membership", foreign_key: :assignee_membership_id, optional: true
    belongs_to :created_by, class_name: "::Membership", foreign_key: :created_by_membership_id, optional: true

    validates :title, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :recurrence_rule, inclusion: { in: RECURRENCE_RULES }
    validates :recurrence_mode, inclusion: { in: RECURRENCE_MODES }, presence: true, if: :recurring?
    validates :recurrence_mode, absence: true, unless: :recurring?
    validates :recurrence_interval, presence: true, numericality: { only_integer: true, greater_than: 0 },
                                     if: -> { recurrence_rule == "every_n_days" }
    validates :recurrence_interval, absence: true, unless: -> { recurrence_rule == "every_n_days" }

    before_validation :default_status, on: :create
    before_save :track_completed_at

    scope :open, -> { where.not(status: "complete") }

    def complete?
      status == "complete"
    end

    def recurring?
      recurrence_rule != "none"
    end

    private

    def default_status
      self.status ||= STATUSES.first
    end

    # completed_at is the anchor date relative recurrence generates the
    # next occurrence from — cleared on reopen so a task that's completed
    # and reopened multiple times doesn't carry a stale timestamp forward.
    def track_completed_at
      return unless will_save_change_to_status?

      self.completed_at = status == "complete" ? (completed_at || Time.current) : nil
    end
  end
end
