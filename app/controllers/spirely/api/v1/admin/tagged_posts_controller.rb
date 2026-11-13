module Spirely
  module Api
    module V1
      module Admin
        # Staff posts that tag children (5ST-78): admins, owners and members
        # with the staff flag post to the tagged children's families, who
        # each get an email. Kids ministry only.
        class TaggedPostsController < BaseController
          include Spirely::FamilyPostPhotosJson
          include Spirely::StaffFamilyPostJson

          before_action { require_module!("kidsmin") }
          before_action :require_staff_poster!

          # POST /api/v1/admin/tagged_posts
          #
          # tagged_post[body], tagged_post[child_ids][], and any
          # tagged_post[photos][] in a multipart body.
          def create
            attrs = params.require(:tagged_post).permit(:body, child_ids: [], photos: [])
            post = Spirely::FamilyPost.post_to_families!(
              church: Current.church, author: Current.membership, body: attrs[:body].to_s.strip,
              child_ids: attrs[:child_ids], photos: attrs[:photos],
            )
            Spirely::TaggedPostNotifier.posted(post)
            render json: post_json(post.reload), status: :created
          rescue ActiveRecord::RecordInvalid, Spirely::FamilyPost::TagError, Spirely::FamilyPost::PhotoError => e
            message = e.is_a?(ActiveRecord::RecordInvalid) && e.record.errors[:body].any? ? "Write a message." : e.message
            render json: { error: message, code: "validation_error" }, status: :unprocessable_entity
          end

          # GET /api/v1/admin/tagged_posts/children?q=em
          #
          # Children to tag, by first or last name.
          def children
            q = params[:q].to_s.strip
            scope = Current.church.children.includes(:family).order(:first_name, :last_name)
            if q.present?
              like = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
              scope = scope.where("first_name ILIKE :q OR last_name ILIKE :q OR (first_name || ' ' || last_name) ILIKE :q", q: like)
            end
            render json: {
              children: scope.limit(20).map { |c|
                { id: c.id, full_name: c.full_name, first_name: c.first_name, family_name: c.family.family_name, no_photos: c.no_photos }
              },
            }
          end

          private

          def require_staff_poster!
            return if admin? || Current.membership&.staff?
            render json: { error: "Forbidden", code: "forbidden" }, status: :forbidden
          end
        end
      end
    end
  end
end
