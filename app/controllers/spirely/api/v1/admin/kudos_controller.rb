module Spirely
  module Api
    module V1
      module Admin
        # Staff Kudos screens (5ST-60): the overview, the people list, one
        # person's balance and history, awarding or deducting points by
        # hand, promo codes (5ST-61) and Settings → Kudos, including the
        # earning rates (5ST-61). Admins only. People are addressed by
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

          # PATCH /api/v1/admin/kudos/settings
          #   { earning_starts_on, checkin_points, group_points, event_rates: [{ pco_event_id, points }],
          #     service_hour_points, service_flat_points, count_rehearsals }
          # Any subset. event_rates replaces every per-event rate. Points for
          # attendance not yet paid follow straight away at the new rates.
          def update_settings
            setting = kudos.setting
            setting.earning_starts_on = Date.iso8601(params[:earning_starts_on]) if params.key?(:earning_starts_on)
            rates = setting.rates.dup
            rates["checkin"] = rate_param(:checkin_points) if params.key?(:checkin_points)
            rates["group_attendance"] = rate_param(:group_points) if params.key?(:group_points)
            rates["service_hour"] = rate_param(:service_hour_points) if params.key?(:service_hour_points)
            rates["service_flat"] = rate_param(:service_flat_points) if params.key?(:service_flat_points)
            if params.key?(:count_rehearsals)
              setting.count_rehearsals = ActiveModel::Type::Boolean.new.cast(params[:count_rehearsals])
            end
            if params.key?(:event_rates)
              rates["checkin_events"] = Array(params[:event_rates]).to_h do |r|
                [r.require(:pco_event_id).to_s, rate_value(r[:points])]
              end
            end
            setting.update!(rates: rates)
            Spirely::KudosEarningJob.perform_later(Current.church.id)
            render json: settings_json
          end

          # GET /api/v1/admin/kudos/promo_codes
          def promo_codes
            codes = Current.church.promo_codes.order(created_at: :desc)
            uses = Current.church.points_entries.where(source: "promo_code", source_type: Spirely::PromoCode.polymorphic_name)
                          .group(:source_id).count
            render json: { promo_codes: codes.map { |c| promo_code_json(c, uses.fetch(c.id, 0)) } }
          end

          # POST /api/v1/admin/kudos/promo_codes  { code?, label, points, max_uses?, expires_on? }
          # A blank code gets a random one.
          def create_promo_code
            code = Current.church.promo_codes.new(
              promo_code_params.merge(created_by_account: Current.account,
                                      created_by_name: Current.account&.name.presence || Current.account&.email),
            )
            code.code = Spirely::PromoCode.generate_code if code.code.blank?
            code.save!
            render json: promo_code_json(code, 0), status: :created
          end

          # PATCH /api/v1/admin/kudos/promo_codes/:id  { label?, max_uses?, expires_on?, active? }
          # The code and its points can't change once made — people may
          # already have claimed it.
          def update_promo_code
            code = Current.church.promo_codes.find(params[:id])
            code.assign_attributes(promo_code_params.except(:code, :points))
            if params.key?(:active)
              code.turned_off_at = ActiveModel::Type::Boolean.new.cast(params[:active]) ? nil : (code.turned_off_at || Time.current)
            end
            code.save!
            render json: promo_code_json(code, code.claims.count)
          end

          private

          def settings_json
            setting = kudos.setting
            names = kudos.checkin_events.index_by { |e| e[:pco_event_id] }
            {
              earning_starts_on: setting.earning_starts_on,
              checkin_points: setting.checkin_points,
              group_points: setting.group_points,
              groups_synced: Current.church.uses_groups?,
              event_rates: setting.checkin_event_points.map do |id, points|
                { pco_event_id: id, event_name: names.dig(id, :event_name) || "Event no longer in Check-Ins", points: points }
              end,
              events: names.values,
              service_hour_points: setting.service_hour_points,
              service_flat_points: setting.service_flat_points,
              count_rehearsals: setting.count_rehearsals,
              services_last_synced_at: Current.church.sync_setting&.services_last_synced_at,
              services_access_denied_at: Current.church.sync_setting&.services_access_denied_at,
            }
          end

          def rate_param(key) = rate_value(params[key])

          # Whole numbers only; the setting validates the range.
          def rate_value(value)
            Integer(value.to_s, exception: false) or raise Spirely::Kudos::Error, "Points must be a whole number."
          end

          def promo_code_params
            attrs = params.permit(:code, :label, :points, :max_uses, :expires_on).to_h.symbolize_keys
            attrs[:max_uses] = attrs[:max_uses].presence if attrs.key?(:max_uses)
            attrs[:expires_on] = attrs[:expires_on].presence && Date.iso8601(attrs[:expires_on]) if attrs.key?(:expires_on)
            attrs
          end

          def promo_code_json(code, uses)
            {
              id: code.id, code: code.code, label: code.label, points: code.points, max_uses: code.max_uses,
              uses: uses, points_given: uses * code.points, expires_on: code.expires_on,
              status: code.status(today: Spirely::ChurchTime.today(Current.church), uses: uses),
              created_by: code.created_by_name, created_at: code.created_at,
            }
          end

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
