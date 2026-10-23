module Spirely
  # Hours one staff member logged (time card). Points at a task when the
  # work was one, and always counts toward a category — the task's, unless
  # the entry has its own.
  class TimeEntry < ApplicationRecord
    MAX_HOURS = 24

    belongs_to :church
    belongs_to :membership, class_name: "::Membership"
    belongs_to :task, class_name: "Spirely::Task", optional: true
    belongs_to :time_category, class_name: "Spirely::TimeCategory"

    before_validation :category_from_task

    validates :title, presence: true, length: { maximum: 120 }
    validates :description, length: { maximum: 2_000 }
    validates :hours, numericality: { greater_than: 0, less_than_or_equal_to: MAX_HOURS }
    validates :worked_on, presence: true
    validate :same_church

    scope :newest_first, -> { order(worked_on: :desc, id: :desc) }

    private

    def category_from_task
      self.time_category ||= task&.time_category
      self.title = task.title if title.blank? && task
    end

    def same_church
      errors.add(:task, "isn't in this church") if task && task.church_id != church_id
      errors.add(:time_category, "isn't in this church") if time_category && time_category.church_id != church_id
      errors.add(:membership, "isn't in this church") if membership && membership.church_id != church_id
    end
  end
end
