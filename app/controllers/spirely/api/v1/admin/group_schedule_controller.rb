module Spirely
  module Api
    module V1
      module Admin
        # Small Groups → Schedule tab (5ST-55): every active group's next few
        # meetings with who's leading and hosting, plus coverage numbers.
        class GroupScheduleController < BaseController
          include ScheduleJson

          before_action :require_admin!
          before_action -> { require_module!("smallgroups") }

          # GET /api/v1/admin/group_schedule?weeks=4
          def show
            weeks  = (params[:weeks] || Spirely::GroupSchedule::WEEKS).to_i
            groups = Current.church.groups.active.includes(:group_type).order(:name).to_a
            data   = groups.to_h { |g| [g, Spirely::GroupSchedule.new(g, weeks: weeks).meetings] }

            render json: {
              summary: schedule_summary(data),
              groups: data.map { |g, meetings|
                {
                  id: g.id, name: g.name, audience: g.audience, schedule_text: g.schedule_text,
                  jobs: g.jobs, people: eligible_json(g),
                  meetings: meetings.map { |m| meeting_json(g, m) },
                }
              },
            }
          end
        end
      end
    end
  end
end
