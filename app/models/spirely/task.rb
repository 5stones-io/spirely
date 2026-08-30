module Spirely
  class Task < ApplicationRecord
    # Canonical Spirely status set (5ST-6) — kept deliberately small and
    # not a 1:1 mirror of any particular PCO Workflow's step sequence,
    # since that sequence varies per workflow and isn't a simple status
    # enum. Mapping this set to/from a synced PCO Workflow card's steps
    # (map_status_in/out) is future PCO-sync work, not built yet.
    STATUSES = %w[not_started in_progress blocked complete].freeze

    belongs_to :church
    belongs_to :assignee,   class_name: "::Membership", foreign_key: :assignee_membership_id, optional: true
    belongs_to :created_by, class_name: "::Membership", foreign_key: :created_by_membership_id, optional: true

    validates :title, presence: true
    validates :status, inclusion: { in: STATUSES }

    before_validation :default_status, on: :create

    scope :open, -> { where.not(status: "complete") }

    def complete?
      status == "complete"
    end

    private

    def default_status
      self.status ||= STATUSES.first
    end
  end
end
