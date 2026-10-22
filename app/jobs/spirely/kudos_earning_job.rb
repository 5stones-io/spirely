module Spirely
  # Posts Kudos points for check-ins and group meetings attended (5ST-61).
  # Runs after every attendance sync and groups sync, and after an admin
  # changes the rates or the earning start date — see
  # Kudos#post_attendance_points!, which is safe to run any number of times.
  class KudosEarningJob < ApplicationJob
    def perform(church_id)
      church = Church.find(church_id)
      return unless church.module_enabled?("kudos")

      posted = Spirely::Kudos.new(church).post_attendance_points!
      Rails.logger.info("[Spirely] KudosEarningJob posted #{posted} entries for church #{church_id}") if posted.positive?
    end
  end
end
