module Spirely
  module Api
    module V1
      module Admin
        # Small Groups → Overview tab (5ST-52): an admin health view of what
        # Planning Center's own Groups reports don't show. Participation,
        # demographics and attendance trends stay in PCO (linked, not
        # copied). Schedule coverage, follow-ups and leader load join this
        # response as phases 4–5 ship.
        class GroupsOverviewController < BaseController
          include GroupsJson
          include ScheduleJson

          ATTENTION_LIST_SIZE = 5

          before_action :require_admin!
          before_action -> { require_module!("smallgroups") }

          # GET /api/v1/admin/groups_overview
          def show
            healths  = Spirely::GroupHealthCalculator.new(Current.church).call
            flagged  = healths.select(&:needs_attention?)
            count_of = ->(key) { flagged.count { |h| h.flags.any? { |f| f.key == key } } }

            render json: {
              needs_attention: {
                groups:          flagged.size,
                no_leader:       count_of.call("no_leader"),
                shrinking:       count_of.call("shrinking"),
                request_waiting: count_of.call("request_waiting"),
                top:             flagged.first(ATTENTION_LIST_SIZE).map { |h| group_summary_json(h) },
              },
              membership: {
                weeks:  Spirely::GroupHealthCalculator::TREND_WINDOW.in_weeks.to_i,
                joined: healths.sum { |h| h.joined.size },
                left:   healths.sum { |h| h.left.size },
              },
              groups_count: healths.size,
              schedule: schedule_overview(healths.map(&:group)),
              pco_reports_url: PCO_GROUPS_REPORTS_URL,
            }
          end

          private

          OPEN_SLOTS_LIST_SIZE = 5

          # Schedule coverage for the next few weeks, plus the soonest spots
          # still needing someone. Nil until any group uses the schedule.
          def schedule_overview(groups)
            scheduling = groups.select { |g| g.schedule_assignments.exists? }
            return nil if scheduling.empty?

            data = scheduling.to_h { |g| [g, Spirely::GroupSchedule.new(g).meetings] }
            open = data.flat_map { |g, ms| ms.flat_map { |m| m[:slots].values.select(&:fillable?).map { |s| [g, m, s] } } }
                       .sort_by { |_g, m, _s| m[:meets_on] }
            schedule_summary(data).merge(
              weeks: Spirely::GroupSchedule::WEEKS,
              open_list: open.first(OPEN_SLOTS_LIST_SIZE).map { |g, m, s|
                { group_id: g.id, group_name: g.name, meets_on: m[:meets_on], label: m[:meets_on].strftime("%a %b %-d"),
                  job_label: s.job_label, status: s.status, person: s.person&.full_name }
              },
            )
          end
        end
      end
    end
  end
end
