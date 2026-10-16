module Spirely
  module Api
    module V1
      module Admin
        # Staff Kudos screens (5ST-60): the overview, the people list, one
        # person's balance and history, awarding or deducting points by
        # hand, and Settings → Kudos. Admins only. People are addressed by
        # their Planning Center person id, since someone can get points
        # before they've been synced as a Spirely::Person.
        class KudosController < BaseController
          include Spirely::KudosJson

          before_action -> { require_module!("kudos") }
          before_action :require_admin!

          PER_PAGE = 50
          HISTORY_PER_PAGE = 25

          # GET /api/v1/admin/kudos
          def overview
            today = Spirely::ChurchTime.today(Current.church)
            entries = Current.church.points_entries
            month = entries.where(occurred_on: today.beginning_of_month..today, source: "manual")
            render json: {
              points_held: entries.sum(:points),
              people_count: entries.distinct.count(:person_id),
              month: {
                awarded: month.credits.sum(:points),
                awards_count: month.credits.count,
                awarders_count: month.credits.distinct.count(:awarded_by_account_id),
                deducted: -month.debits.sum(:points),
                deductions_count: month.debits.count,
              },
              earning_starts_on: kudos.setting.earning_starts_on,
              recent: entries.includes(:person).order(id: :desc).limit(5).map { |e| points_entry_json(e, with_person: true) },
            }
          end

          # GET /api/v1/admin/kudos/people?audience=kids|adults&q=&page=
          # Without a search: everyone who has points, highest balance
          # first. With one: anyone matching, points or not.
          def people
            kid = { "kids" => true, "adults" => false }[params[:audience]]
            if params[:q].present?
              found = kudos.recipients(query: params[:q], limit: PER_PAGE)
              found = found.select { |r| !!r.kid == kid } unless kid.nil?
              render json: { people: rows_for(found), meta: nil }
            else
              scope = Current.church.people.joins(:points_entries).group("spirely_people.id")
                             .select("spirely_people.*, SUM(spirely_points_entries.points) AS balance")
                             .order("balance DESC, spirely_people.id").page(params[:page]).per(PER_PAGE)
              scope = scope.where(child: kid) unless kid.nil?
              by_id = kudos.recipients(pco_ids: scope.map(&:pco_person_id), limit: PER_PAGE).index_by(&:pco_person_id)
              render json: {
                people: rows_for(scope.map { |p| by_id[p.pco_person_id] }.compact),
                meta: pagination_meta(scope),
              }
            end
          end

          # GET /api/v1/admin/kudos/people/:pco_person_id?page=
          def person
            found = kudos.recipient(params[:pco_person_id]) or raise ActiveRecord::RecordNotFound
            history = found.person ? kudos.history(found.person).page(params[:page]).per(HISTORY_PER_PAGE) : nil
            render json: person_json(found).merge(
              kudos.totals(found.person),
              parents: kudos.parents_of(found),
              earning_starts_on: kudos.setting.earning_starts_on,
              deductions_count: found.person ? found.person.points_entries.debits.count : 0,
              history: history ? history.map { |e| points_entry_json(e) } : [],
              more_history: history&.next_page.present?,
            )
          end

          # POST /api/v1/admin/kudos/entries  { pco_person_id, points, note }
          # points is signed: negative deducts.
          def create_entry
            entry = kudos.award!(pco_person_id: params.require(:pco_person_id), points: params.require(:points),
                                 note: params[:note], by_account: Current.account)
            render json: points_entry_json(entry, with_person: true).merge(balance: kudos.totals(entry.person)[:balance]),
                   status: :created
          end

          # GET /api/v1/admin/kudos/settings
          def settings
            render json: settings_json
          end

          # PATCH /api/v1/admin/kudos/settings  { earning_starts_on }
          def update_settings
            kudos.setting.update!(earning_starts_on: Date.iso8601(params.require(:earning_starts_on)))
            render json: settings_json
          end

          private

          def settings_json = { earning_starts_on: kudos.setting.earning_starts_on }

          def rows_for(recipients)
            people = recipients.filter_map(&:person)
            balances = kudos.balances(people.map(&:id))
            latest = Current.church.points_entries.where(person_id: people.map(&:id))
                            .select("DISTINCT ON (person_id) *").order(:person_id, occurred_on: :desc, id: :desc).index_by(&:person_id)
            recipients.map do |r|
              last = r.person && latest[r.person.id]
              person_json(r).merge(
                balance: r.person ? balances.fetch(r.person.id, 0) : 0,
                last_entry: last && { points: last.points, occurred_on: last.occurred_on },
              )
            end
          end

          def person_json(r)
            {
              pco_person_id: r.pco_person_id, person_id: r.person&.id, name: r.name, first_name: r.first_name,
              kid: !!r.kid, grade: r.grade, household: r.family&.family_name,
            }
          end

          rescue_from ActiveRecord::RecordNotFound do
            render json: { error: "Not found", code: "not_found" }, status: :not_found
          end
          rescue_from Spirely::Kudos::Error, ActiveRecord::RecordInvalid, Date::Error, ActionController::ParameterMissing do |e|
            render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
          end
        end
      end
    end
  end
end
