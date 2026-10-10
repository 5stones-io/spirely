module Spirely
  # Keeps attendance follow-ups (Spirely::GroupNudge, 5ST-53) up to date
  # for one church: opens one for anyone GroupNudgeCalculator newly flags
  # (owned by the group's head leader) and refreshes the numbers on ones
  # still open. Never closes them — people do that by logging what
  # happened. Runs after every groups sync, so it sees fresh attendance.
  class GroupNudgeSyncJob < ApplicationJob
    def perform(church_id)
      church = Church.find(church_id)
      return unless church.module_enabled?("smallgroups")

      Spirely::GroupNudgeCalculator.new(church).call.each do |result|
        nudge = church.group_nudges.open.find_by(group: result.group, person: result.person)
        if nudge
          nudge.update!(metrics: result.metrics)
        else
          nudge = church.group_nudges.create!(group: result.group, person: result.person, metrics: result.metrics,
                                              owner_person: result.group.head_leader)
          nudge.notes.create!(church: church, author_name: "Spirely",
                              body: "Follow-up created: missed #{result.metrics['missed_streak']} meetings in a row.")
        end
      end
    end
  end
end
