module Spirely
  module Api
    module V1
      # My Points (Kudos, 5ST-60): the signed-in adult's own balance and
      # history, plus each of their kids' — parents see (and, once the
      # store arrives, spend) their kids' points. Only the account's own
      # family's kids are ever included.
      class MyPointsController < BaseController
        include Spirely::KudosJson

        before_action -> { require_module!("kudos") }

        HISTORY_LIMIT = 50

        # GET /api/v1/my_points
        def show
          people = []
          if (own = own_pco_person_id)
            people << person_json("you", own, current_person&.pco_person_id == own ? current_person : Current.church.people.find_by(pco_person_id: own),
                                  first_name: current_person&.first_name || current_guardian&.first_name || current_family&.primary_contact_first_name)
          end
          current_family&.children&.order(:birthdate, :first_name)&.each do |child|
            person = child.pco_person_id.present? ? Current.church.people.find_by(pco_person_id: child.pco_person_id) : nil
            people << person_json("child", "child-#{child.id}", person, first_name: child.first_name, name: child.full_name)
          end

          if people.empty?
            return render json: { error: "We couldn't match you to Planning Center — ask your church staff.", code: "person_not_found" },
                          status: :not_found
          end

          render json: {
            family_name: current_family&.family_name,
            earning_starts_on: kudos.setting.earning_starts_on,
            people: people,
          }
        end

        private

        # The signed-in adult's own Planning Center id: their synced Person,
        # else the guardian or primary-contact record they signed in as.
        def own_pco_person_id
          current_person&.pco_person_id.presence ||
            (current_guardian ? current_guardian.pco_person_id : current_family&.pco_person_id).presence
        end

        def person_json(relation, key, person, first_name:, name: nil)
          {
            key: key, relation: relation, first_name: first_name, name: name || person&.full_name || first_name,
            **kudos.totals(person),
            history: person ? kudos.history(person).limit(HISTORY_LIMIT).map { |e| points_entry_json(e) } : [],
          }
        end
      end
    end
  end
end
