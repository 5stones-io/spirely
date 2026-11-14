module Spirely
  # Family post photos as the family feed and staff's review list show
  # them. Each link carries a 15-minute signed token, minted only in an
  # answer that was already allowed to show the post: another family's
  # post only appears once it's approved, so its photos stay hidden until
  # then too. FamilyPostPhotosController serves the token.
  module FamilyPostPhotosJson
    extend ActiveSupport::Concern

    private

    def post_photos_json(post)
      post.ordered_photos.map do |photo|
        token = photo.blob.signed_id(expires_in: 15.minutes, purpose: "family_post_photo")
        { id: photo.id, url: "#{request.base_url}/api/v1/family_post_photos/#{token}" }
      end
    end
  end
end
