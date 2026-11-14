require "rails_helper"

# Staff posts that tag children (5ST-78): admins, owners and members with
# the staff flag post; the tagged children's families get an email.
RSpec.describe "Admin tagged posts API", type: :request do
  include ActiveJob::TestHelper

  let(:church) { create(:church, name: "Grace Church", enabled_modules: ["kidsmin"]) }
  let(:admin)  { create(:account, first_name: "Maria", last_name: "Rivera") }
  let(:emma_family) { create(:spirely_family, church: church, family_name: "Singleton", email: "singletons@example.com") }
  let(:noah_family) { create(:spirely_family, church: church, family_name: "Torres", email: "torres@example.com") }
  let!(:emma) { create(:spirely_child, family: emma_family, first_name: "Emma", last_name: "Singleton") }
  let!(:noah) { create(:spirely_child, family: noah_family, first_name: "Noah", last_name: "Torres") }

  before do
    create(:membership, :admin, church: church, account: admin)
    use_tenant_host!(church)
  end

  def json = JSON.parse(response.body)
  def photo = fixture_file_upload("store-item.png", "image/png")

  def post_to_families(as: admin, child_ids: [emma.id, noah.id], photos: nil)
    params = { tagged_post: { body: "Psalm 23 crafts today!", child_ids: child_ids } }
    params[:tagged_post][:photos] = photos if photos
    post "/api/v1/admin/tagged_posts", params: params, headers: auth_headers(as)
  end

  describe "POST /api/v1/admin/tagged_posts" do
    it "posts to the tagged children's families and emails each family once" do
      create(:spirely_guardian, family: emma_family, email: "dad@example.com")
      create(:spirely_guardian, family: emma_family, email: "singletons@example.com")

      perform_enqueued_jobs { post_to_families(photos: [photo]) }

      expect(response).to have_http_status(:created)
      expect(json).to include("audience" => "tagged", "status" => "approved", "author_name" => "Maria Rivera", "family" => nil)
      expect(json["tagged_children"]).to contain_exactly(
        include("id" => emma.id, "first_name" => "Emma", "family_name" => "Singleton"),
        include("id" => noah.id, "first_name" => "Noah", "family_name" => "Torres"),
      )
      expect(json["photos"].size).to eq(1)

      mails = ActionMailer::Base.deliveries
      expect(mails.map(&:to).flatten).to contain_exactly("singletons@example.com", "dad@example.com", "torres@example.com")
      emma_mail = mails.find { |m| m.to == ["singletons@example.com"] }
      expect(emma_mail.subject).to eq("Maria Rivera posted about Emma")
    ensure
      ActionMailer::Base.deliveries.clear
    end

    it "is open to members with the staff flag, not other members" do
      staff = create(:account)
      create(:membership, church: church, account: staff, staff: true)
      post_to_families(as: staff)
      expect(response).to have_http_status(:created)

      parent = create(:account)
      create(:membership, church: church, account: parent)
      post_to_families(as: parent)
      expect(response).to have_http_status(:forbidden)
    end

    it "needs the kids ministry module" do
      church.update!(enabled_modules: [])
      post_to_families
      expect(response).to have_http_status(:not_found)
    end

    it "won't post photos of a child whose family asked for none" do
      emma.update!(no_photos: true)

      post_to_families(photos: [photo])
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("Emma's family asked for no photos. Remove the photos or untag Emma to post.")

      post_to_families
      expect(response).to have_http_status(:created)
    end
  end

  describe "GET /api/v1/admin/tagged_posts/children" do
    it "finds this church's children by name, with their family and no-photos flag" do
      emma.update!(no_photos: true)
      create(:spirely_child, family: create(:spirely_family), first_name: "Emmett")

      get "/api/v1/admin/tagged_posts/children?q=em", headers: auth_headers(admin)

      expect(json["children"]).to eq([
        {
          "id" => emma.id, "full_name" => "Emma Singleton", "first_name" => "Emma", "family_name" => "Singleton",
          "no_photos" => true, "age" => 8, "grade" => emma.grade_display, "parents" => [], "possible_duplicate" => false,
        },
      ])
    end

    # The same name can belong to different children, or to one child
    # entered twice in Planning Center. Age, grade and parents tell them
    # apart; the same name and birthday marks a likely duplicate.
    it "gives staff what they need to tell children with the same name apart" do
      emma.update!(birthdate: Date.new(2014, 4, 1), grade: 3)
      create(:spirely_guardian, family: emma_family, first_name: "Clive")
      create(:spirely_guardian, family: emma_family, first_name: "Ann")
      second_record = create(:spirely_child, family: create(:spirely_family, church: church, family_name: "Singleton"),
                                             first_name: "emma", last_name: "SINGLETON", birthdate: Date.new(2014, 4, 1), grade: 6)
      other_emma  = create(:spirely_child, family: noah_family, first_name: "Emma", last_name: "Singleton", birthdate: Date.new(2007, 7, 30))
      no_birthday = create(:spirely_child, family: noah_family, first_name: "Emma", last_name: "Singleton", birthdate: nil)
      # Another church's child with the same name and birthday doesn't count.
      create(:spirely_child, family: create(:spirely_family), first_name: "Emma", last_name: "Singleton", birthdate: Date.new(2007, 7, 30))

      travel_to(Date.new(2026, 11, 14)) do
        get "/api/v1/admin/tagged_posts/children", params: { q: "emma singleton" }, headers: auth_headers(admin)
      end

      by_id = json["children"].index_by { |c| c["id"] }
      expect(by_id.keys).to contain_exactly(emma.id, second_record.id, other_emma.id, no_birthday.id)
      expect(by_id[emma.id]).to include("age" => 12, "grade" => "3rd", "parents" => %w[Ann Clive], "possible_duplicate" => true)
      expect(by_id[second_record.id]).to include("grade" => "6th", "possible_duplicate" => true)
      expect(by_id[other_emma.id]).to include("age" => 19, "possible_duplicate" => false)
      expect(by_id[no_birthday.id]).to include("age" => nil, "possible_duplicate" => false)
    end
  end

  it "shows tagged posts in staff's Family Posts with everyone tagged" do
    post_to_families
    get "/api/v1/admin/family_posts", headers: auth_headers(admin)

    tagged = json["family_posts"].sole
    expect(tagged).to include("family" => nil, "author_name" => "Maria Rivera", "staff_post" => true)
    expect(tagged["tagged_children"].map { |c| c["first_name"] }).to contain_exactly("Emma", "Noah")
  end

  # The "Post to families" page for staff who aren't admins: what they've
  # posted, newest first. Other people's posts and family posts aren't theirs.
  describe "GET /api/v1/admin/tagged_posts" do
    let(:staff) { create(:account, first_name: "Jon", last_name: "Park").tap { |a| create(:membership, church: church, account: a, staff: true) } }

    it "lists the member's own posts to families, newest first" do
      post_to_families(as: staff, child_ids: [emma.id])
      older = Spirely::FamilyPost.last
      older.update!(created_at: 2.days.ago)
      post_to_families(as: staff, child_ids: [emma.id, noah.id])
      newer = Spirely::FamilyPost.last
      post_to_families(as: admin)
      create(:spirely_family_post, church: church, family: emma_family, status: "approved")

      get "/api/v1/admin/tagged_posts", headers: auth_headers(staff)

      expect(response).to have_http_status(:ok)
      expect(json["family_posts"].map { |p| p["id"] }).to eq([newer.id, older.id])
      expect(json["family_posts"].first).to include("author_name" => "Jon Park", "staff_post" => true)
      expect(json["family_posts"].first["tagged_children"].map { |c| c["first_name"] }).to contain_exactly("Emma", "Noah")
      expect(json["meta"]).to include("total_count" => 2)
    end

    it "is closed to members who can't post to families" do
      get "/api/v1/admin/tagged_posts", headers: auth_headers(create(:account).tap { |a| create(:membership, church: church, account: a) })
      expect(response).to have_http_status(:forbidden)
    end
  end
end
