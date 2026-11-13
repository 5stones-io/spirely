module Spirely
  # A child tagged in a staff post (5ST-78). The child's family sees the post.
  class FamilyPostChild < ApplicationRecord
    belongs_to :church
    belongs_to :family_post, class_name: "Spirely::FamilyPost"
    belongs_to :child, class_name: "Spirely::Child"

    validates :child_id, uniqueness: { scope: :family_post_id }
  end
end
