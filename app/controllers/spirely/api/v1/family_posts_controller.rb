module Spirely
  module Api
    module V1
      # v1 scope (5ST-9): the family-authored news feed itself — create/
      # read/update/destroy for the posting family. Staff moderation
      # (approve/reject the queue) is a separate controller,
      # Admin::FamilyPostsController, since it's a different role with a
      # different view of the same table.
      class FamilyPostsController < BaseController
        include Spirely::FamilyPostPhotosJson

        before_action :require_family!
        before_action :set_own_post, only: %i[update destroy answer]
        before_action :set_visible_post, only: %i[show pray stop_praying remove_tags]

        # GET /api/v1/family_posts?post_type=praise_report
        # (several types: post_type=prayer_request,praise_report)
        #
        # The church-wide feed: every approved, church-audience post from
        # any family, PLUS this family's own posts regardless of status/
        # audience — a family should always be able to see their own
        # pending/rejected/staff_only posts, just not anyone else's.
        def index
          scope = Current.church.family_posts.visible_to_family(current_family)
          scope = scope.where(post_type: params[:post_type].to_s.split(",")) if params[:post_type].present?

          posts = scope.includes(:family, :guardian, :child, :answers_post, :tagged_children, { author: :account }, photos_attachments: :blob)
                        .order(created_at: :desc)
                        .page(params[:page]).per(25)
          @praying_ids = Spirely::FamilyPostPrayer.where(account_id: Current.account.id, family_post_id: posts.map(&:id))
                                                  .pluck(:family_post_id).to_set

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
        #
        # Photos come as family_post[photos][] in a multipart body. They're
        # checked before any is uploaded, and a bad one saves nothing.
        def create
          post = current_family.family_posts.new(post_params)
          post.church = Current.church
          post.guardian = current_guardian
          FamilyPost.transaction do
            post.save!
            post.attach_photos(photo_params[:photos]) if photo_params[:photos].present?
          end

          render json: post_json(post), status: :created
        rescue ActiveRecord::RecordInvalid, FamilyPost::PhotoError => e
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
          unless @family_post.editable?
            return render json: { error: "This post has already been reviewed and can no longer be edited",
                                   code: "already_moderated" }, status: :unprocessable_entity
          end

          # Only this post's own photos; ids from anywhere else are ignored.
          removed = @family_post.photos_attachments.where(id: Array(photo_params[:remove_photo_ids])).to_a
          FamilyPost.transaction do
            @family_post.update!(post_params)
            removed.each(&:delete)
            @family_post.photos_attachments.reset
            @family_post.attach_photos(photo_params[:photos]) if photo_params[:photos].present?
          end
          # The files go only once the change has saved.
          removed.each { |a| a.blob.purge_later }
          render json: post_json(@family_post.reload)
        rescue ActiveRecord::RecordInvalid, FamilyPost::PhotoError => e
          render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
        end

        # POST /api/v1/family_posts/:id/prayer
        #
        # "I'm praying": another family's prayer request this family can see.
        def pray
          if @family_post.family_id == current_family.id
            return render json: { error: "You can't pray for your own request here.", code: "own_post" },
                          status: :unprocessable_entity
          end
          @family_post.pray!(Current.account)
          render json: prayer_json(@family_post)
        rescue FamilyPost::PrayerError => e
          render json: { error: e.message, code: "validation_error" }, status: :unprocessable_entity
        end

        # DELETE /api/v1/family_posts/:id/prayer
        def stop_praying
          @family_post.stop_praying!(Current.account)
          render json: prayer_json(@family_post)
        end

        # POST /api/v1/family_posts/:id/answer
        #
        # Marks the family's own prayer request answered. With
        # answer[share_as_praise], answer[note] (and any answer[photos][])
        # also go out as a praise report.
        def answer
          answer = params.fetch(:answer, {}).permit(:note, :share_as_praise, photos: [])
          praise = @family_post.mark_answered!(
            note: answer[:note], share_as_praise: ActiveModel::Type::Boolean.new.cast(answer[:share_as_praise]),
            guardian: current_guardian, photos: answer[:photos],
          )
          @praying_ids = Set.new
          render json: { family_post: post_json(@family_post.reload), praise_report: praise && post_json(praise.reload) }
        rescue ActiveRecord::RecordInvalid, FamilyPost::PrayerError, FamilyPost::PhotoError => e
          message = e.is_a?(ActiveRecord::RecordInvalid) && e.record.errors[:body].any? ? "Say what happened to share it as a praise report." : e.message
          render json: { error: message, code: "validation_error" }, status: :unprocessable_entity
        end

        # DELETE /api/v1/family_posts/:id/tags
        #
        # Takes this family's children off a staff post (5ST-78), so it
        # leaves this family's feed.
        def remove_tags
          unless @family_post.staff_post?
            return render json: { error: "Only staff posts have tags.", code: "not_tagged" }, status: :unprocessable_entity
          end
          @family_post.remove_tags!(current_family)
          head :no_content
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
          @family_post = Current.church.family_posts.visible_to_family(current_family).find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Post not found", code: "not_found" }, status: :not_found
        end

        def post_params
          params.require(:family_post).permit(:post_type, :audience, :body, :child_id)
        end

        def photo_params
          params.require(:family_post).permit(photos: [], remove_photo_ids: [])
        end

        def prayer_json(post)
          { praying: post.praying?(Current.account), prayer_count: post.reload.prayers_count }
        end

        def post_json(post)
          {
            id:          post.id,
            post_type:   post.post_type,
            audience:    post.audience,
            status:      post.status,
            body:        post.body,
            family_id:   post.family_id,
            mine:        post.family_id == current_family.id,
            editable:    post.family_id == current_family.id && post.editable?,
            child:       post.child && { id: post.child.id, first_name: post.child.first_name },
            author_name: Spirely::FamilyPost.author_name(post),
            # A staff post (5ST-78): only this family's own tagged children.
            staff_post:  post.staff_post?,
            tagged_children: post.tagged_children.select { |c| c.family_id == current_family.id }
                                 .sort_by(&:first_name).map { |c| { id: c.id, first_name: c.first_name } },
            rejected_reason: post.rejected_reason,
            photos:      post_photos_json(post),
            prayer_count: post.prayers_count,
            praying:     @praying_ids ? @praying_ids.include?(post.id) : post.praying?(Current.account),
            answered_at: post.answered_at,
            answer_note: post.answer_note,
            answers_post: post.answers_post && {
              id: post.answers_post.id, body: post.answers_post.body,
              created_at: post.answers_post.created_at, prayer_count: post.answers_post.prayers_count,
            },
            created_at:  post.created_at,
            updated_at:  post.updated_at,
          }
        end
      end
    end
  end
end
