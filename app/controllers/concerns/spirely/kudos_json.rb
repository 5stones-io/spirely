module Spirely
  # JSON shapes shared by the staff Kudos screens and My Points (5ST-60).
  module KudosJson
    extend ActiveSupport::Concern

    private

    def kudos = @kudos ||= Spirely::Kudos.new(Current.church)

    def points_entry_json(entry, with_person: false)
      json = {
        id: entry.id, points: entry.points, note: entry.note, source: entry.source,
        occurred_on: entry.occurred_on, by: entry.awarded_by_name, created_at: entry.created_at,
      }
      json[:balance_after] = entry.balance_after.to_i if entry.has_attribute?(:balance_after)
      json[:person] = { pco_person_id: entry.person.pco_person_id, name: entry.person.full_name } if with_person
      json
    end
  end
end
