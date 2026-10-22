module Spirely
  # Posts Kudos points for check-ins and group meetings attended (5ST-61)
  # and time served on Services plans (5ST-62).
  # Runs after every attendance, groups and services sync, and after an admin
  # changes the rates or the earning start date — see
  # Kudos#post_earned_points!, which is safe to run any number of times.
  class KudosEarningJob < ApplicationJob
    def perform(church_id)
      church = Church.find(church_id)
      return unless church.module_enabled?("kudos")

      posted = Spirely::Kudos.new(church).post_earned_points!
      Rails.logger.info("[Spirely] KudosEarningJob posted #{posted} entries for church #{church_id}") if posted.positive?
    end
  end
end
