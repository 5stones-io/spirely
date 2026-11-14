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

    # Who logged the hours, for screens: their name, else their email.
    def person_name(membership) = real_name(membership) || membership.account.email

    # Their name, or nil: the account's own, else that of the one Planning
    # Center person with the same email (accounts made without an invite
    # have no name). Skipped when several people share the email, as
    # spouses often do, rather than guess.
    def real_name(membership)
      @real_names ||= {}
      return @real_names[membership.account_id] if @real_names.key?(membership.account_id)

      account = membership.account
      @real_names[membership.account_id] = account.name.presence || begin
        matches = Current.church.people.where("LOWER(email) = ?", account.email.to_s.downcase).limit(2).to_a
        matches.one? ? matches.first.full_name.presence : nil
      end
    end

    # Hours per category, biggest first.
    def totals_by_category(entries)
      entries.group_by(&:time_category).map { |c, list| { category: time_category_json(c), hours: list.sum(&:hours).to_f } }
             .sort_by { |t| -t[:hours] }
    end
  end
end
