module Spirely
  # JSON shapes shared by the Small Groups admin endpoints (GroupsController,
  # GroupsOverviewController), built from GroupHealthCalculator::Health.
  module GroupsJson
    extend ActiveSupport::Concern

    PCO_GROUPS_URL         = "https://groups.planningcenteronline.com/groups".freeze
    PCO_GROUPS_REPORTS_URL = "https://groups.planningcenteronline.com/reports".freeze

    private

    def group_summary_json(health)
      group = health.group
      {
        id:              group.id,
        name:            group.name,
        audience:        group.audience,
        group_type_id:   group.group_type_id,
        group_type_name: group.group_type&.name,
        schedule_text:   group.schedule_text,
        leaders:         health.leaders.map(&:full_name),
        members_count:   health.members_count,
        members_trend:   health.trend,
        flags:           health.flags.map(&:to_h),
      }
    end

    def group_detail_json(health)
      group = health.group
      group_summary_json(health).merge(
        description:      group.description,
        location_name:    group.location_name,
        trend_weeks:      Spirely::GroupHealthCalculator::TREND_WINDOW.in_weeks.to_i,
        leaders_detail:   health.leaders.map { |p| { name: p.full_name, email: p.email } },
        joined:           health.joined.map { |m| { name: m.person.full_name, at: m.joined_at } },
        left:             health.left.map { |m| { name: m.person.full_name, at: m.left_at } },
        pending_requests: health.pending_requests.map { |a|
          { id: a.id, name: a.person.full_name, applied_at: a.applied_at, message: a.message }
        },
        pco_url:          "#{PCO_GROUPS_URL}/#{group.pco_group_id}",
      )
    end
  end
end
