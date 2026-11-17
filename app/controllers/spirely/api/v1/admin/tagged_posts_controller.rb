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
          before_action { require_feature!("family_posts") }
          before_action :require_staff_poster!

          # GET /api/v1/admin/tagged_posts
          #
          # The signed-in member's own posts to families, newest first: the
          # "Post to families" page for staff who aren't admins (admins also
          # see them in Family Posts).
          def index
            posts = Current.church.family_posts.where(author_membership_id: Current.membership&.id)
              .includes(:answers_post, { author: :account }, { tagged_children: :family }, photos_attachments: :blob)
              .order(created_at: :desc).page(params[:page]).per(50)
            @praying_ids = Set.new
            render json: { family_posts: posts.map { |p| post_json(p) }, meta: pagination_meta(posts) }
          end

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
          # Children to tag, by first or last name. Different children can
          # share a name, and Planning Center can hold one child twice, so
          # each comes with age, grade and parents, and possible_duplicate
          # when another child here has the same name and birthday.
          def children
            q = params[:q].to_s.strip
            scope = Current.church.children.includes(family: :guardians).order(:first_name, :last_name, :id)
            if q.present?
              like = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
              scope = scope.where("first_name ILIKE :q OR last_name ILIKE :q OR (first_name || ' ' || last_name) ILIKE :q", q: like)
            end
            kids = scope.limit(20).to_a
            duplicates = duplicate_ids(kids)
            render json: {
              children: kids.map { |c|
                {
                  id: c.id, full_name: c.full_name, first_name: c.first_name, family_name: c.family.family_name,
                  no_photos: c.no_photos, age: c.age, grade: c.grade_display,
                  parents: c.family.guardians.map(&:first_name).sort,
                  possible_duplicate: duplicates.include?(c.id),
                }
              },
            }
          end

          private

          # Of these children, the ones sharing a name (ignoring case) and a
          # birthday with another child at this church.
          def duplicate_ids(kids)
            dated = kids.select(&:birthdate)
            return Set.new if dated.empty?

            key = ->(first, last, born) { [first.to_s.strip.downcase, last.to_s.strip.downcase, born] }
            counts = Current.church.children
              .where(birthdate: dated.map(&:birthdate).uniq)
              .where("LOWER(TRIM(first_name)) IN (?)", dated.map { |c| c.first_name.to_s.strip.downcase }.uniq)
              .pluck(:first_name, :last_name, :birthdate)
              .map { |row| key.(*row) }.tally
            dated.select { |c| counts.fetch(key.(c.first_name, c.last_name, c.birthdate), 0) > 1 }.map(&:id).to_set
          end

          def require_staff_poster!
            return if admin? || Current.membership&.staff?
            render json: { error: "Forbidden", code: "forbidden" }, status: :forbidden
          end
        end
      end
    end
  end
end
