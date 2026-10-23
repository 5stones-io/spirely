module Spirely
  # JSON shapes shared by the time card and the admin hours report.
  module TimeCardJson
    extend ActiveSupport::Concern

    private

    def time_category_json(category)
      { id: category.id, code: category.code, name: category.name, active: category.archived_at.nil? }
    end

    def time_entry_json(entry, with_person: false)
      json = {
        id: entry.id, title: entry.title, description: entry.description, hours: entry.hours.to_f,
        worked_on: entry.worked_on, created_at: entry.created_at,
        category: time_category_json(entry.time_category),
        task: entry.task && { id: entry.task.id, title: entry.task.title },
      }
      if with_person
        json[:person] = { membership_id: entry.membership_id, name: person_name(entry.membership),
                          email: entry.membership.account.email }
      end
      json
    end

    def person_name(membership) = membership.account.name.presence || membership.account.email

    # Hours per category, biggest first.
    def totals_by_category(entries)
      entries.group_by(&:time_category).map { |c, list| { category: time_category_json(c), hours: list.sum(&:hours).to_f } }
             .sort_by { |t| -t[:hours] }
    end
  end
end
