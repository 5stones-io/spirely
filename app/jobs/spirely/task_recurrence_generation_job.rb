module Spirely
  # Scheduled sweep for absolute-recurrence Tasks (5ST-7) — generates the
  # next occurrence for any task whose due_date has passed, regardless of
  # whether it was ever completed ("submit the report on the 1st no
  # matter what"). Relative-recurrence tasks are never touched here; they
  # regenerate from TasksController#update on actual completion instead.
  #
  # Registering this on a schedule (sidekiq-cron) is a host-app concern —
  # this gem has no sidekiq-cron dependency of its own, same reasoning as
  # the existing kidsmin sync jobs. See spirely-cloud's
  # config/initializers/sidekiq.rb for the actual cron entry.
  class TaskRecurrenceGenerationJob < ApplicationJob
    def perform
      Spirely::Task
        .where(recurrence_mode: "absolute", next_occurrence_generated_at: nil)
        .where("due_date <= ?", Date.current)
        .find_each { |task| Spirely::TaskRecurrenceGenerator.call(task) }
    end
  end
end
