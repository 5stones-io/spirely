module Spirely
  module Api
    module V1
      module Admin
        # Staff's view of the family-authored news feed (5ST-9) — sees
        # every post regardless of audience/status (unlike the
        # family-facing FamilyPostsController, which only ever shows a
        # given family its own posts plus the church-wide approved feed),
        # and can approve/reject/remove.
        #
        # Pastors-only posts are for pastors (5ST-79). Pastors who aren't
        # admins can read and pray for approved prayer requests and praise
        # reports here, and do nothing else.
        class FamilyPostsController < BaseController
          include Spirely::FamilyPostPhotosJson
          include Spirely::StaffFamilyPostJson

          before_action :require_admin!, except: %i[index show pray stop_praying]
          before_action :require_admin_or_pastor!, only: %i[index show pray stop_praying]
          before_action :set_post, only: %i[show destroy approve reject pray stop_praying]

          # GET /api/v1/admin/family_posts?status=pending&post_type=prayer_request
          def index
            scope = staff_scope.includes(:family, :guardian, :child, :answers_post, { author: :account },
                                                         { tagged_children: :family }, photos_attachments: :blob)
            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.where(post_type: params[:post_type].to_s.split(",")) if params[:post_type].present?
            scope = scope.where(audience: params[:audience]) if params[:audience].present?

            # Pending posts oldest-first (a real queue to work through);
            # everything else newest-first, matching the family-facing
            # feed's own ordering.
            posts = if params[:status] == "pending"
                      scope.order(created_at: :asc)
                    else
                      scope.order(created_at: :desc)
                    end.page(params[:page]).per(50)
            @praying_ids = Spirely::FamilyPostPrayer.where(account_id: Current.account.id, family_post_id: posts.map(&:id))
                                                    .pluck(:family_post_id).to_set

            render json: {
              family_posts: posts.map { |p| post_json(p) },
              meta: pagination_meta(posts),
            }
          end

          # GET /api/v1/admin/family_posts/:id
          def show
            render json: post_json(@family_post)
          end

          # POST /api/v1/admin/family_posts/:id/approve
          def approve
            @family_post.approve!(Current.membership)
            render json: post_json(@family_post)
          end

          # POST /api/v1/admin/family_posts/:id/reject
          def reject
            @family_post.reject!(Current.membership, reason: params[:reason])
            render json: post_json(@family_post)
          end

          # POST /api/v1/admin/family_posts/:id/prayer
          #
          # Staff pray for requests too (5ST-79), staff-only ones included.
          def pray
            @family_post.pray!(Current.account)
            render json: prayer_json
          rescue FamilyPost::PrayerError => e
            render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
          end

          # DELETE /api/v1/admin/family_posts/:id/prayer
          def stop_praying
            @family_post.stop_praying!(Current.account)
            render json: prayer_json
          end

          # DELETE /api/v1/admin/family_posts/:id
          #
          # For content that shouldn't have been posted at all (distinct
          # from #reject, which keeps the record and tells the family
          # why) — a hard remove, same as a family can do to their own.
          def destroy
            @family_post.destroy!
            head :no_content
          end

          private

          def require_admin_or_pastor!
            return if admin? || Current.membership&.pastor?
            render json: { error: "Forbidden", code: "forbidden" }, status: :forbidden
          end

          def staff_scope
            scope = Current.church.family_posts.visible_to_staff(Current.membership)
            admin? ? scope : scope.where(post_type: FamilyPost::PRAYER_TYPES, status: "approved")
          end

          def set_post
            @family_post = staff_scope.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render json: { error: "Post not found", code: "not_found" }, status: :not_found
          end

          def prayer_json
            { praying: @family_post.praying?(Current.account), prayer_count: @family_post.reload.prayers_count }
          end
        end
      end
    end
  end
end
