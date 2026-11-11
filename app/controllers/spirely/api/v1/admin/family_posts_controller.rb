module Spirely
  module Api
    module V1
      module Admin
        # Staff's view of the family-authored news feed (5ST-9) — sees
        # every post regardless of audience/status (unlike the
        # family-facing FamilyPostsController, which only ever shows a
        # given family its own posts plus the church-wide approved feed),
        # and can approve/reject/remove.
        class FamilyPostsController < BaseController
          include Spirely::FamilyPostPhotosJson

          before_action :require_admin!
          before_action :set_post, only: %i[show destroy approve reject pray stop_praying]

          # GET /api/v1/admin/family_posts?status=pending&post_type=prayer_request
          def index
            scope = Current.church.family_posts.includes(:family, :guardian, :child, :answers_post, photos_attachments: :blob)
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

          def set_post
            @family_post = Current.church.family_posts.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render json: { error: "Post not found", code: "not_found" }, status: :not_found
          end

          def prayer_json
            { praying: @family_post.praying?(Current.account), prayer_count: @family_post.reload.prayers_count }
          end

          def post_json(post)
            {
              id:          post.id,
              post_type:   post.post_type,
              audience:    post.audience,
              status:      post.status,
              body:        post.body,
              family:      { id: post.family_id, name: post.family.family_name },
              child:       post.child && { id: post.child.id, first_name: post.child.first_name },
              author_name: post.guardian ? "#{post.guardian.first_name} #{post.guardian.last_name}".strip : post.family.primary_contact_name,
              rejected_reason: post.rejected_reason,
              photos:      post_photos_json(post),
              prayer_count: post.prayers_count,
              praying:     @praying_ids ? @praying_ids.include?(post.id) : post.praying?(Current.account),
              answered_at: post.answered_at,
              answer_note: post.answer_note,
              answers_post: post.answers_post && { id: post.answers_post.id, body: post.answers_post.body, created_at: post.answers_post.created_at },
              moderated_at: post.moderated_at,
              moderated_by: post.moderated_by && { id: post.moderated_by.id, email: post.moderated_by.account.email, name: post.moderated_by.account.name },
              created_at:  post.created_at,
              updated_at:  post.updated_at,
            }
          end
        end
      end
    end
  end
end
