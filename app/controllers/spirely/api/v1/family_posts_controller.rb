module Spirely
  module Api
    module V1
      # v1 scope (5ST-9): the family-authored news feed itself — create/
      # read/update/destroy for the posting family. Staff moderation
      # (approve/reject the queue) is a separate controller,
      # Admin::FamilyPostsController, since it's a different role with a
      # different view of the same table.
      class FamilyPostsController < BaseController
        before_action :require_family!
        before_action :set_own_post, only: %i[update destroy]
        before_action :set_visible_post, only: %i[show]

        # GET /api/v1/family_posts?post_type=praise_report
        #
        # The church-wide feed: every approved, church-audience post from
        # any family, PLUS this family's own posts regardless of status/
        # audience — a family should always be able to see their own
        # pending/rejected/staff_only posts, just not anyone else's.
        def index
          scope = Current.church.family_posts
                          .where("(status = ? AND audience = ?) OR family_id = ?",
                                 "approved", "church", current_family.id)
          scope = scope.where(post_type: params[:post_type]) if params[:post_type].present?

          posts = scope.includes(:family, :guardian, :child)
                        .order(created_at: :desc)
                        .page(params[:page]).per(25)

          render json: {
            family_posts: posts.map { |p| post_json(p) },
            meta: pagination_meta(posts),
          }
        end

        # GET /api/v1/family_posts/:id
        def show
          render json: post_json(@family_post)
        end

        # POST /api/v1/family_posts
        def create
          post = current_family.family_posts.new(post_params)
          post.church = Current.church
          post.guardian = current_guardian
          post.save!

          render json: post_json(post), status: :created
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
        end

        # PATCH /api/v1/family_posts/:id
        #
        # Only while still pending moderation (or auto-approved and never
        # touched by staff) — once a post has actually been through
        # moderation (approved or rejected), editing is out of v1 scope;
        # the family deletes and reposts instead. Keeps "what did staff
        # actually approve" unambiguous without a re-moderation flow.
        def update
          unless @family_post.pending? || @family_post.moderated_at.nil?
            return render json: { error: "This post has already been reviewed and can no longer be edited",
                                   code: "already_moderated" }, status: :unprocessable_entity
          end

          @family_post.update!(post_params)
          render json: post_json(@family_post)
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
        end

        # DELETE /api/v1/family_posts/:id
        def destroy
          @family_post.destroy!
          head :no_content
        end

        private

        def set_own_post
          @family_post = current_family.family_posts.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Post not found", code: "not_found" }, status: :not_found
        end

        def set_visible_post
          @family_post = Current.church.family_posts
                                 .where("(status = ? AND audience = ?) OR family_id = ?",
                                        "approved", "church", current_family.id)
                                 .find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Post not found", code: "not_found" }, status: :not_found
        end

        def post_params
          params.require(:family_post).permit(:post_type, :audience, :body, :child_id)
        end

        def post_json(post)
          {
            id:          post.id,
            post_type:   post.post_type,
            audience:    post.audience,
            status:      post.status,
            body:        post.body,
            family_id:   post.family_id,
            child:       post.child && { id: post.child.id, first_name: post.child.first_name },
            author_name: post.guardian ? "#{post.guardian.first_name} #{post.guardian.last_name}".strip : post.family.primary_contact_name,
            rejected_reason: post.rejected_reason,
            created_at:  post.created_at,
            updated_at:  post.updated_at,
          }
        end
      end
    end
  end
end
