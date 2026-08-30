module Spirely
  # Spawns the next occurrence of a recurring Task (5ST-7). Two distinct
  # callers, matching the two recurrence_mode values:
  #
  # - "relative": TasksController#update calls this right after a
  #   recurring task's status is set to "complete" — the next occurrence
  #   is due N days/weeks after the actual completed_at.
  # - "absolute": Spirely::TaskRecurrenceGenerationJob calls this from a
  #   scheduled sweep for every absolute-recurrence task whose due_date
  #   has passed — completion status never matters for this mode ("submit
  #   the report on the 1st no matter what").
  #
  # `next_occurrence_generated_at` is the idempotency guard both paths
  # share — a second call for the same task (a retried completion
  # request, or the sweep job running twice before due_date rolls over)
  # is a no-op, not a duplicate task.
  class TaskRecurrenceGenerator
    def self.call(task)
      return unless task.recurring?
      return if task.next_occurrence_generated_at.present?

      anchor_date = task.recurrence_mode == "relative" ? task.completed_at&.to_date : task.due_date
      return unless anchor_date

      next_due_date = next_due_date_for(task.recurrence_rule, task.recurrence_interval, anchor_date)

      Spirely::Task.transaction do
        series_id = task.recurrence_series_id ||= SecureRandom.uuid

        next_task = task.church.tasks.create!(
          title:                 task.title,
          description:           task.description,
          due_date:              next_due_date,
          assignee_membership_id: task.assignee_membership_id,
          created_by_membership_id: task.created_by_membership_id,
          recurrence_rule:       task.recurrence_rule,
          recurrence_interval:   task.recurrence_interval,
          recurrence_mode:       task.recurrence_mode,
          recurrence_series_id:  series_id
        )

        task.update!(recurrence_series_id: series_id, next_occurrence_generated_at: Time.current)
        next_task
      end
    end

    def self.next_due_date_for(rule, interval, anchor_date)
      case rule
      when "daily"    then anchor_date + 1.day
      when "weekly"   then anchor_date + 1.week
      when "biweekly" then anchor_date + 2.weeks
      when "monthly"  then anchor_date + 1.month
      when "every_n_days" then anchor_date + interval.days
      else
        raise ArgumentError, "next_due_date_for called with a non-recurring rule: #{rule.inspect}"
      end
    end
  end
end
