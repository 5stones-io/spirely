module Spirely
  # Someone saying they're praying for a prayer request (5ST-79). One per
  # account and post; the post keeps the count in prayers_count.
  class FamilyPostPrayer < ApplicationRecord
    belongs_to :church
    belongs_to :family_post, class_name: "Spirely::FamilyPost", counter_cache: :prayers_count
    belongs_to :account, class_name: "::Account"

    validates :account_id, uniqueness: { scope: :family_post_id }
  end
end
