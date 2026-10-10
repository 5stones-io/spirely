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
              pco_reports_url: PCO_GROUPS_REPORTS_URL,
            }
          end
        end
      end
    end
  end
end
