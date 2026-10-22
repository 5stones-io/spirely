module Spirely
  # A leader of a PCO Services team, read by PcoServicesSyncJob. Leaders
  # get the Kudos shout-out allowance (5ST-64), like Groups leaders.
  class ServiceTeamLeader < ApplicationRecord
    belongs_to :church
    belongs_to :person, class_name: "Spirely::Person"

    validates :pco_team_id, presence: true
  end
end
