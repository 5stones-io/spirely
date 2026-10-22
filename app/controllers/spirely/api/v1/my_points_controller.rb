module Spirely
  module Api
    module V1
      # My Points (Kudos, 5ST-60): the signed-in adult's own balance and
      # history, plus each of their kids' — parents see (and, once the
      # store arrives, spend) their kids' points. Only the account's own
      # family's kids are ever included. Promo codes are claimed here too
      # (5ST-61), for yourself or one of your kids.
      class MyPointsController < BaseController
        include Spirely::KudosJson

        before_action -> { require_module!("kudos") }

        HISTORY_LIMIT = 50

        # GET /api/v1/my_points
        def show
          people = people_json
          if people.empty?
            return render json: { error: "We couldn't match you to Planning Center — ask your church staff.", code: "person_not_found" },
                          status: :not_found
          end

          render json: payload(people)
        end

        # POST /api/v1/my_points/claim  { code, key }
        # key is a person's key from #show: yours, or "child-<id>". Answers
        # with #show's payload plus what was claimed, so the screen can
        # just re-render.
        def claim
          pco_person_id = claim_pco_person_id(params.require(:key).to_s) or
            return render json: { error: "We can't add points for them yet — ask your church staff.", code: "not_found" },
                          status: :not_found

          entry = kudos.claim_code!(code: params[:code], pco_person_id: pco_person_id)
          render json: payload(people_json).merge(claimed: { key: params[:key], points: entry.points, note: entry.note }),
                 status: :created
        rescue Spirely::Kudos::Error => e
          render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
        end

        private

        def payload(people)
          { family_name: current_family&.family_name, earning_starts_on: kudos.setting.earning_starts_on, people: people }
        end

        def people_json
          people = []
          if (own = own_pco_person_id)
            people << person_json("you", own, current_person&.pco_person_id == own ? current_person : Current.church.people.find_by(pco_person_id: own),
                                  first_name: current_person&.first_name || current_guardian&.first_name || current_family&.primary_contact_first_name)
          end
          current_family&.children&.order(:birthdate, :first_name)&.each do |child|
            person = child.pco_person_id.present? ? Current.church.people.find_by(pco_person_id: child.pco_person_id) : nil
            people << person_json("child", "child-#{child.id}", person, first_name: child.first_name, name: child.full_name)
          end
          people
        end

        # Only the signed-in adult themself or a kid in their own family.
        def claim_pco_person_id(key)
          if (child_id = key[/\Achild-(\d+)\z/, 1])
            current_family&.children&.find_by(id: child_id)&.pco_person_id.presence
          elsif key == own_pco_person_id
            key
          end
        end

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
