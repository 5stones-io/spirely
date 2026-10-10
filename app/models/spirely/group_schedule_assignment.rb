require "digest"

module Spirely
  # One job at one group meeting (Small Groups module, 5ST-55): who leads,
  # hosts, or brings refreshments on a given date, and whether they've
  # accepted. Keyed on (group, meets_on, job) rather than the PCO event, so
  # a repeating PCO event being regenerated just re-links group_event.
  #
  # The accept/decline link token is stored only as a SHA-256 digest; a new
  # one is issued whenever the slot is (re)assigned, so an old link stops
  # working the moment someone else is asked.
  class GroupScheduleAssignment < ApplicationRecord
    JOBS = {
      "lead"         => { label: "Lead",         verb: "lead" },
      "host_home"    => { label: "Host home",    verb: "host" },
      "refreshments" => { label: "Refreshments", verb: "bring refreshments for" },
    }.freeze
    HOSTING_JOBS = %w[host_home refreshments].freeze
    STATUSES     = %w[open pending accepted declined].freeze
    SOURCES      = %w[staff head_leader self].freeze

    belongs_to :church
    belongs_to :group, class_name: "Spirely::Group"
    belongs_to :group_event, class_name: "Spirely::GroupEvent", optional: true
    belongs_to :person, class_name: "Spirely::Person", optional: true
    belongs_to :assigned_by_account, class_name: "::Account", optional: true

    validates :job, inclusion: { in: JOBS.keys }
    validates :status, inclusion: { in: STATUSES }
    validates :source, inclusion: { in: SOURCES }, allow_nil: true
    validates :meets_on, presence: true, uniqueness: { scope: [:group_id, :job] }

    def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

    # Only finds a slot whose current link this is.
    def self.find_by_token(token)
      return nil if token.blank?
      find_by(token_digest: digest(token))
    end

    def job_label = JOBS.dig(job, :label)
    def job_verb  = JOBS.dig(job, :verb)

    # Open for someone new to take: never filled, or turned down.
    def fillable? = status.in?(%w[open declined])

    # A fresh 22-character link token for this assignment, valid until the
    # end of the meeting day in the church's time zone.
    def issue_token!
      token = SecureRandom.urlsafe_base64(16)
      update!(token_digest: self.class.digest(token),
              token_expires_at: Spirely::ChurchTime.zone(church).parse(meets_on.to_s).end_of_day)
      token
    end

    # Accept/decline links work until the meeting day ends.
    def answerable?
      person_id.present? && status.in?(%w[pending accepted declined]) &&
        token_expires_at.present? && token_expires_at > Time.current
    end
  end
end
