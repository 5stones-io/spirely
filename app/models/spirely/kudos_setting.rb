module Spirely
  # A church's Kudos settings (5ST-60), one row per church, created the
  # first time anything reads them. Earning rates arrive with the phases
  # that use them (check-ins, groups, serving).
  class KudosSetting < ApplicationRecord
    belongs_to :church

    validates :earning_starts_on, presence: true

    # Defaults the earning start date to today, so turning the module on
    # doesn't pay out years of history unless the church moves it back.
    def self.for(church)
      church.kudos_setting || church.create_kudos_setting!(earning_starts_on: Spirely::ChurchTime.today(church))
    rescue ActiveRecord::RecordNotUnique
      church.reload.kudos_setting
    end
  end
end
