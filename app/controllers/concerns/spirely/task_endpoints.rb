module Spirely
  # Shared by the admin tasks API and staff's own (my_tasks).
  module TaskEndpoints
    extend ActiveSupport::Concern

    private

    def update_task!(task, attrs)
      task.update!(attrs)

      # Relative recurrence regenerates off actual completion; absolute
      # recurrence is due-date-driven regardless of completion (see
      # Spirely::TaskRecurrenceGenerationJob) so it's never triggered here.
      if task.saved_change_to_status? && task.complete? && task.recurrence_mode == "relative"
        Spirely::TaskRecurrenceGenerator.call(task)
      end
    end

    def check_time_category!(attrs)
      return if attrs[:time_category_id].blank?
      raise ActiveRecord::RecordNotFound unless Current.church.time_categories.exists?(id: attrs[:time_category_id])
    end

    def task_json(task)
      {
        id:          task.id,
        title:       task.title,
        description: task.description,
        status:      task.status,
        due_date:    task.due_date,
        assignee:    task.assignee && { id: task.assignee.id, email: task.assignee.account.email, name: task.assignee.account.name },
        created_by:  task.created_by && { id: task.created_by.id, email: task.created_by.account.email, name: task.created_by.account.name },
        recurrence_rule:     task.recurrence_rule,
        recurrence_interval: task.recurrence_interval,
        recurrence_mode:     task.recurrence_mode,
        recurrence_series_id: task.recurrence_series_id,
        sync_to_pco: task.sync_to_pco,
        time_category: task.time_category && { id: task.time_category.id, code: task.time_category.code, name: task.time_category.name },
        completed_at: task.completed_at,
        created_at:  task.created_at,
        updated_at:  task.updated_at,
      }
    end
  end
end
