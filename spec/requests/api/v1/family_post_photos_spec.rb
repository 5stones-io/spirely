require "rails_helper"

# Photos on family posts: up to 10 images, 5 MB each, stored under the
# church's own key prefix and shown through short-lived signed links.
RSpec.describe "Family post photos", type: :request do
  include ActiveJob::TestHelper

  let(:church)  { create(:church, family_posts_moderation_enabled: true) }
  let(:account) { create(:account) }
  let!(:family) { create(:spirely_family, church: church, account: account) }

  before { use_tenant_host!(church) }

  def json = JSON.parse(response.body)
  def photo = fixture_file_upload("store-item.png", "image/png")
  def path_of(url) = URI(url).path

  def create_post(photos)
    post "/api/v1/family_posts",
         params: { family_post: { post_type: "praise_report", body: "Championship!", photos: photos } },
         headers: auth_headers(account)
  end

  it "adds photos to a new post under the church's own key prefix, in order" do
    create_post([photo, photo, photo])

    expect(response).to have_http_status(:created)
    expect(json["photos"].size).to eq(3)
    expect(json["photos"].map { |p| p["id"] }).to eq(json["photos"].map { |p| p["id"] }.sort)
    post_record = church.family_posts.sole
    expect(post_record.photos.map { |p| p.blob.key }).to all(start_with("church-#{church.id}/posts/"))
  end

  it "serves a photo through its signed link, which stops working after 15 minutes" do
    create_post([photo])
    url = json["photos"].first["url"]
    expect(url).to start_with("http://#{church.slug}.")

    get path_of(url)
    expect(response).to have_http_status(:found)

    travel 16.minutes do
      get path_of(url)
      expect(response).to have_http_status(:not_found)
    end
  end

  it "won't open a photo with a token minted for something else" do
    create_post([photo])
    blob = church.family_posts.sole.photos.first.blob
    get "/api/v1/family_post_photos/#{blob.signed_id(purpose: 'incident_photo')}"
    expect(response).to have_http_status(:not_found)
  end

  it "rejects more than 10 photos, and saves nothing" do
    create_post(Array.new(11) { photo })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["error"]).to eq("A post can have up to 10 photos.")
    expect(church.family_posts.count).to eq(0)
    expect(ActiveStorage::Blob.count).to eq(0)
  end

  it "rejects a file that isn't an image, whatever it claims to be" do
    text = Rack::Test::UploadedFile.new(StringIO.new("not a picture"), "image/png", original_filename: "x.png")
    create_post([photo, text])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["error"]).to eq("Photos have to be pictures (JPG, PNG, GIF, WebP or HEIC).")
    expect(church.family_posts.count).to eq(0)
  end

  it "rejects a photo over 5 MB" do
    big = Tempfile.new(["big", ".png"])
    big.binmode
    big.write(File.binread(file_fixture("store-item.png")))
    big.write("\0" * 5.megabytes)
    big.rewind
    create_post([Rack::Test::UploadedFile.new(big.path, "image/png")])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["error"]).to eq("Each photo has to be under 5 MB.")
  ensure
    big&.close!
  end

  it "adds and removes photos while editing a post that's still waiting for review" do
    create_post([photo, photo])
    id = json["id"]
    first, second = json["photos"].map { |p| p["id"] }

    patch "/api/v1/family_posts/#{id}",
          params: { family_post: { body: "Champions!", photos: [photo], remove_photo_ids: [first] } },
          headers: auth_headers(account)

    expect(response).to have_http_status(:ok)
    expect(json["body"]).to eq("Champions!")
    expect(json["photos"].size).to eq(2)
    expect(json["photos"].first["id"]).to eq(second)
  end

  it "counts the photos a post already has toward the 10" do
    create_post(Array.new(9) { photo })
    id = json["id"]

    patch "/api/v1/family_posts/#{id}", params: { family_post: { photos: [photo, photo] } },
                                        headers: auth_headers(account)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(church.family_posts.sole.photos.count).to eq(9)
  end

  it "ignores photo ids from another post" do
    other = create(:spirely_family_post, church: church, family: create(:spirely_family, church: church))
    other.attach_photos([photo])
    create_post([photo])

    patch "/api/v1/family_posts/#{json['id']}",
          params: { family_post: { remove_photo_ids: [other.photos.first.id] } },
          headers: auth_headers(account)
    expect(other.reload.photos.count).to eq(1)
  end

  it "keeps another family's photos hidden until the post is approved" do
    other_account = create(:account)
    create(:spirely_family, church: church, account: other_account)
    create_post([photo])
    id = json["id"]

    get "/api/v1/family_posts", headers: auth_headers(other_account)
    expect(json["family_posts"]).to be_empty

    church.family_posts.find(id).approve!(nil)
    get "/api/v1/family_posts", headers: auth_headers(other_account)
    expect(json["family_posts"].sole["photos"].size).to eq(1)
  end

  it "shows staff the photos of a post waiting for review" do
    admin = create(:account)
    create(:membership, :admin, church: church, account: admin)
    create_post([photo, photo])

    get "/api/v1/admin/family_posts", params: { status: "pending" }, headers: auth_headers(admin)
    expect(json["family_posts"].sole["photos"].size).to eq(2)
  end

  it "deletes the photos along with the post" do
    create_post([photo, photo])

    perform_enqueued_jobs do
      delete "/api/v1/family_posts/#{json['id']}", headers: auth_headers(account)
    end
    expect(response).to have_http_status(:no_content)
    expect(ActiveStorage::Blob.count).to eq(0)
  end
end
