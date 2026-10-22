module Spirely
  module Api
    module V1
      module Admin
        # Staff side of the Kudos store (5ST-63): the catalog, the pickup
        # queue, and checkout at a table. Admins only, like the rest of
        # the staff Kudos screens.
        class KudosStoreController < BaseController
          include Spirely::KudosJson

          before_action -> { require_module!("kudos") }
          before_action :require_admin!

          ORDERS_PER_PAGE = 50

          # GET /api/v1/admin/kudos/store/items
          def items
            items = Current.church.store_items.ordered.includes(image_attachment: :blob)
            render json: { items: items.map { |i| store_item_json(i, staff: true) } }
          end

          # POST /api/v1/admin/kudos/store/items  (multipart when there's an image)
          def create_item
            item = Current.church.store_items.new(item_params)
            item.position = Current.church.store_items.maximum(:position).to_i + 1
            Spirely::StoreItem.transaction do
              item.save!
              item.attach_image(params[:image]) if params[:image].present?
              store.add_codes!(item, params[:codes]) if params[:codes].present?
            end
            render json: store_item_json(item.reload, staff: true), status: :created
          end

          # PATCH /api/v1/admin/kudos/store/items/:id
          #   any of the item fields, hidden (bool), image (file), remove_image (bool), codes (text, appended)
          def update_item
            item = Current.church.store_items.find(params[:id])
            Spirely::StoreItem.transaction do
              item.assign_attributes(item_params.except(:kind))
              item.hidden_at = boolean(params[:hidden]) ? (item.hidden_at || Time.current) : nil if params.key?(:hidden)
              item.save!
              item.attach_image(params[:image]) if params[:image].present?
              item.image.purge_later if boolean(params[:remove_image]) && params[:image].blank?
              store.add_codes!(item, params[:codes]) if params[:codes].present?
            end
            render json: store_item_json(item.reload, staff: true)
          end

          # GET /api/v1/admin/kudos/store/orders?status=pending|all&page=
          # Pending is the pickup queue, oldest first; all is newest first.
          def orders
            scope = Current.church.store_orders.includes(:item, :person, :codes)
            scope = params[:status] == "all" ? scope.newest_first : scope.pending.order(:created_at, :id)
            page = scope.page(params[:page]).per(ORDERS_PER_PAGE)
            render json: {
              orders: page.map { |o| store_order_json(o, with_person: true) },
              pending_count: Current.church.store_orders.pending.count,
              more: page.next_page.present?,
            }
          end

          # POST /api/v1/admin/kudos/store/orders/:id/fulfill
          def fulfill
            order = store.fulfill!(Current.church.store_orders.find(params[:id]), by_account: Current.account)
            render json: store_order_json(order, with_person: true)
          end

          # POST /api/v1/admin/kudos/store/orders/:id/cancel
          def cancel
            order = store.cancel!(Current.church.store_orders.find(params[:id]), by_account: Current.account)
            render json: store_order_json(order, with_person: true)
          end

          # POST /api/v1/admin/kudos/store/checkout  { pco_person_id, lines: [{ item_id, quantity }] }
          def checkout
            pco_person_id = params.require(:pco_person_id).to_s
            lines = Array(params[:lines]).map { |l| { item_id: l[:item_id], quantity: l[:quantity] } }
            orders = store.checkout!(pco_person_id: pco_person_id, lines: lines, by_account: Current.account)
            render json: {
              orders: orders.map { |o| store_order_json(o, with_person: true) },
              balance: kudos.totals(orders.first.person)[:balance],
            }, status: :created
          end

          private

          def store = @store ||= Spirely::KudosStore.new(Current.church)

          def item_params
            attrs = params.permit(:name, :description, :points, :kind, :stock, :instructions, :per_person_limit, :audience)
                          .to_h.symbolize_keys
            %i[stock per_person_limit].each { |k| attrs[k] = attrs[k].presence if attrs.key?(k) }
            attrs
          end

          def boolean(value) = ActiveModel::Type::Boolean.new.cast(value)

          rescue_from ActiveRecord::RecordNotFound do
            render json: { error: "Not found", code: "not_found" }, status: :not_found
          end
          rescue_from Spirely::Kudos::Error, ActiveRecord::RecordInvalid, ActionController::ParameterMissing do |e|
            render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
          end
        end
      end
    end
  end
end
