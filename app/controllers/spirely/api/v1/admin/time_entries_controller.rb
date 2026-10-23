require "csv"

module Spirely
  module Api
    module V1
      module Admin
        # Everyone's time card hours for admins: filter by person, category
        # and dates, with totals, and a CSV for payroll.
        class TimeEntriesController < BaseController
          include Spirely::TimeCardJson

          before_action :require_admin!

          MAX_ROWS = 2_000

          # GET /api/v1/admin/time_entries?from=&to=&membership_id=&time_category_id=
          # GET /api/v1/admin/time_entries.csv?…
          # Defaults to the last two weeks.
          def index
            from, to = date_range
            entries = Current.church.time_entries.where(worked_on: from..to).includes(:time_category, :task, membership: :account)
            entries = entries.where(membership_id: params[:membership_id]) if params[:membership_id].present?
            entries = entries.where(time_category_id: params[:time_category_id]) if params[:time_category_id].present?
            entries = entries.newest_first.limit(MAX_ROWS).to_a

            return send_csv(entries, from, to) if request.format.csv? || params[:format] == "csv"

            render json: {
              from: from, to: to,
              entries: entries.map { |e| time_entry_json(e, with_person: true) },
              total_hours: entries.sum(&:hours).to_f,
              totals: totals_by_category(entries),
              people_totals: entries.group_by(&:membership).map { |m, list| { membership_id: m.id, name: person_name(m), hours: list.sum(&:hours).to_f } }
                                    .sort_by { |t| -t[:hours] },
              people: time_card_people.map { |m| { membership_id: m.id, name: person_name(m) } },
              categories: Current.church.time_categories.ordered.map { |c| time_category_json(c) },
            }
          end

          private

          def date_range
            today = Spirely::ChurchTime.today(Current.church)
            from = params[:from].present? ? Date.iso8601(params[:from]) : today - 13
            to   = params[:to].present? ? Date.iso8601(params[:to]) : today
            from > to ? [to, from] : [from, to]
          rescue Date::Error
            [today - 13, today]
          end

          def time_card_people
            Current.church.memberships.includes(:account)
                   .where(role: %w[admin owner]).or(Current.church.memberships.where(staff: true))
                   .sort_by { |m| person_name(m).downcase }
          end

          def send_csv(entries, from, to)
            csv = CSV.generate do |rows|
              rows << ["Date", "Name", "Email", "Category code", "Category", "Task", "Title", "Description", "Hours"]
              entries.sort_by { |e| [e.worked_on, person_name(e.membership)] }.each do |e|
                rows << [e.worked_on.iso8601, person_name(e.membership), e.membership.account.email, e.time_category.code,
                         e.time_category.name, e.task&.title, e.title, e.description, e.hours.to_f]
              end
            end
            send_data csv, type: "text/csv", filename: "time-card-#{from.iso8601}-to-#{to.iso8601}.csv"
          end
        end
      end
    end
  end
end
