module Spirely
  module Api
    module V1
      # The recognition page (Kudos, 5ST-64): the church's public shout-out
      # feed, your own sent and received ones (and your kids'), giving a
      # shout-out, and leaderboards once staff turn them on.
      #
      # Anyone signed in can thank someone, but outside staff only people
      # they share a group or Services team with — so this never becomes a
      # search of the whole church.
      class RecognitionController < BaseController
        include Spirely::KudosJson

        before_action -> { require_module!("kudos") }

        RECIPIENTS_LIMIT = 10
        TEAM_WINDOW = 26.weeks

        # GET /api/v1/recognition
        def show
          allowance = viewer.person && recognition.allowance_left(viewer.person)
          render json: {
            feed: recognition.feed.map { |s| shout_out_json(s) },
            mine: recognition.mine(viewer).map { |s| shout_out_json(s) },
            allowance: allowance && { monthly: recognition.setting.leader_allowance, left: allowance },
            leaderboards_enabled: recognition.setting.leaderboards_enabled || admin?,
            leaderboard_scopes: recognition.setting.leaderboards_enabled || admin? ? recognition.leaderboard_scopes : [],
          }
        end

        # GET /api/v1/recognition/recipients?q=
        def recipients
          render json: { people: recipients_for(params[:q].to_s.strip) }
        end

        # POST /api/v1/shout_outs  { to_pco_person_id, message, visibility, points }
        def create
          to = params.require(:to_pco_person_id).to_s
          unless admin? || allowed_people.exists?(pco_person_id: to)
            return render json: { error: "You can thank people in your groups and teams.", code: "not_found" }, status: :not_found
          end

          shout = recognition.give!(viewer: viewer, to_pco_person_id: to, message: params[:message],
                                    visibility: params[:visibility].presence || "public", points: params[:points])
          allowance = viewer.person && recognition.allowance_left(viewer.person)
          render json: { shout_out: shout_out_json(shout), allowance: allowance && { monthly: recognition.setting.leader_allowance, left: allowance } },
                 status: :created
        rescue Spirely::Kudos::Error, ActiveRecord::RecordNotFound => e
          render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
        end

        # GET /api/v1/recognition/leaderboard?period=month|year&audience=adults|kids&scope=group:<id>|team:<id>
        def leaderboard
          unless recognition.setting.leaderboards_enabled || admin?
            return render json: { error: "Leaderboards aren't turned on.", code: "not_found" }, status: :not_found
          end

          kind, id = params[:scope].to_s.split(":", 2)
          rows = recognition.leaderboard(
            period: params[:period] == "year" ? "year" : "month", kids: params[:audience] == "kids",
            group_id: (Current.church.groups.find(id).id if kind == "group"), pco_team_id: (id if kind == "team"),
          )
          render json: { rows: rows }
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Not found", code: "not_found" }, status: :not_found
        end

        private

        def recognition = @recognition ||= Spirely::Recognition.new(Current.church)

        def viewer
          @viewer ||= Spirely::Recognition::Viewer.new(
            account: Current.account, person: current_person, staff: admin?,
            kid_person_ids: Current.church.people.where(pco_person_id: kid_pco_ids).pluck(:id),
          )
        end

        def kid_pco_ids = current_family ? current_family.children.where.not(pco_person_id: [nil, ""]).pluck(:pco_person_id) : []

        # People in the viewer's current groups and the Services teams they
        # served on lately, plus their own kids.
        def allowed_people
          person = viewer.person
          ids = Current.church.people.where(pco_person_id: kid_pco_ids).select(:id)
          return Current.church.people.where(id: ids) unless person

          memberships = Current.church.group_memberships.current
          group_ids = memberships.where(person: person).joins(:group).merge(Spirely::Group.active).select(:group_id)
          team_ids = Current.church.service_plan_people.joins(:plan)
                            .where(person: person, spirely_service_plans: { sort_date: TEAM_WINDOW.ago.. }).select(:pco_team_id)
          led_team_ids = Current.church.service_team_leaders.where(person: person).select(:pco_team_id)
          teammates = Current.church.service_plan_people.joins(:plan).where(spirely_service_plans: { sort_date: TEAM_WINDOW.ago.. })
                             .where(pco_team_id: team_ids).or(Current.church.service_plan_people.joins(:plan)
                             .where(spirely_service_plans: { sort_date: TEAM_WINDOW.ago.. }).where(pco_team_id: led_team_ids))
                             .select(:person_id)
          Current.church.people.where.not(id: person.id).where.not(pco_person_id: [nil, ""])
                 .where(id: memberships.where(group_id: group_ids).select(:person_id))
                 .or(Current.church.people.where.not(id: person.id).where.not(pco_person_id: [nil, ""]).where(id: teammates))
                 .or(Current.church.people.where(id: ids))
        end

        def recipients_for(query)
          if admin?
            return [] if query.length < 2

            return Spirely::Kudos.new(Current.church).recipients(query: query, limit: RECIPIENTS_LIMIT).map do |r|
              { pco_person_id: r.pco_person_id, name: r.name, kid: !!r.kid }
            end
          end

          scope = allowed_people
          if query.present?
            like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
            scope = scope.where("COALESCE(first_name, '') || ' ' || COALESCE(last_name, '') ILIKE ?", like)
          end
          scope.order(:first_name, :last_name).limit(RECIPIENTS_LIMIT).map do |p|
            { pco_person_id: p.pco_person_id, name: p.full_name, kid: !!p.child }
          end
        end
      end
    end
  end
end
