module Spirely
  # A family post as staff see it, in Family Posts and after posting a
  # staff post (5ST-78). Includers also include FamilyPostPhotosJson.
  module StaffFamilyPostJson
    extend ActiveSupport::Concern

    private

    def post_json(post)
      {
        id:          post.id,
        post_type:   post.post_type,
        audience:    post.audience,
        status:      post.status,
        body:        post.body,
        family:      post.family && { id: post.family_id, name: post.family.family_name },
        child:       post.child && { id: post.child.id, first_name: post.child.first_name },
        author_name: Spirely::FamilyPost.author_name(post),
        # A staff post that tags children (5ST-78), and everyone it tags.
        staff_post:  post.staff_post?,
        tagged_children: post.tagged_children.sort_by(&:first_name).map { |c|
          { id: c.id, first_name: c.first_name, last_name: c.last_name, family_name: c.family.family_name }
        },
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
