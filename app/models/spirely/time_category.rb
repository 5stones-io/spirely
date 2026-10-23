module Spirely
  # A category code that time card hours count toward (the church's stand-in
  # for a billing code), e.g. "FAC · Facilities". Tasks carry one too.
  # Turned off rather than deleted, so past hours keep their code.
  class TimeCategory < ApplicationRecord
    belongs_to :church
    has_many :tasks, class_name: "Spirely::Task", dependent: :restrict_with_error
    has_many :time_entries, class_name: "Spirely::TimeEntry", dependent: :restrict_with_error

    normalizes :code, with: ->(c) { c.to_s.strip.upcase }

    validates :code, presence: true, length: { maximum: 12 }, format: { with: /\A[A-Z0-9._-]+\z/, allow_blank: true },
                     uniqueness: { scope: :church_id }
    validates :name, presence: true, length: { maximum: 60 }

    scope :active, -> { where(archived_at: nil) }
    scope :ordered, -> { order(:code) }

    def label = "#{code} · #{name}"
  end
end
