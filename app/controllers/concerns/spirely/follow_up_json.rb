module Spirely
  # JSON for attendance follow-ups (Spirely::GroupNudge, 5ST-53), shared by
  # the staff Follow-ups tab, My Groups and the overview.
  module FollowUpJson
    extend ActiveSupport::Concern

    private

    def follow_up_json(nudge, detail: false)
      json = {
        id:           nudge.id,
        group:        { id: nudge.group_id, name: nudge.group.name },
        person:       { id: nudge.person_id, name: nudge.person.full_name },
        metrics:      nudge.metrics,
        owner:        nudge.owner_person && { id: nudge.owner_person_id, name: nudge.owner_person.full_name },
        created_at:   nudge.created_at,
        came_back_on: nudge.open? ? nudge.came_back_on&.to_date : nil,
        resolution:   nudge.resolution,
        resolved_at:  nudge.resolved_at,
      }
      return json unless detail

      json.merge(
        contact: { email: nudge.person.email, phone: nudge.person.phone },
        owner_options: nudge.group.current_leaders.map { |p| { id: p.id, name: p.full_name, head_leader: p == nudge.group.head_leader } },
        history: nudge.notes.map { |n| { at: n.created_at, author: n.author_name, body: n.body, outcome: n.outcome } },
      )
    end

    def log_follow_up(nudge)
      nudge.log!(account: Current.account, body: params[:body], outcome: params[:outcome].presence)
      render json: follow_up_json(nudge.reload, detail: true)
    rescue ArgumentError => e
      render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
    end
  end
end
