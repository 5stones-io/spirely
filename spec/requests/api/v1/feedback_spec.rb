require "rails_helper"

# Feedback and requests (5ST-80): anyone at a church sends feedback, with
# pictures and documents, and sees their own submissions' status.
RSpec.describe "Feedback API", type: :request do
  include ActiveJob::TestHelper

  let(:church)  { create(:church, name: "Grace Church") }
  let(:account) { create(:account, first_name: "Megan", last_name: "Torres") }
  let!(:family) { create(:spirely_family, church: church, account: account, family_name: "Torres") }

  before { use_tenant_host!(church) }

  def json = JSON.parse(response.body)

  def upload(name, type = "application/octet-stream")
    fixture_file_upload(name, type)
  end

  def send_feedback(as: account, **attrs)
    post "/api/v1/feedback",
         params: { feedback: { category: "reflection", tone: "went_well", about: "Trunk or Treat · Sat, Oct 25",
                               body: "The candy table ran out by 7:15." }.merge(attrs) },
         headers: auth_headers(as)
  end

  describe "POST /api/v1/feedback" do
    it "saves a parent's feedback with its attachments" do
      send_feedback(attachments: [upload("store-item.png"), upload("supply-list.pdf")])

      expect(response).to have_http_status(:created)
      expect(json).to include("category" => "reflection", "tone" => "went_well", "about" => "Trunk or Treat · Sat, Oct 25",
                              "body" => "The candy table ran out by 7:15.", "status" => "new", "attachment_count" => 2)
      feedback = church.feedbacks.sole
      expect(feedback).to have_attributes(account: account, family: family, sender_role: "parent")
    end

    it "is open to staff and other members with no family" do
      staff = create(:account)
      create(:membership, :admin, church: church, account: staff)
      send_feedback(as: staff, category: "supplies", tone: nil, about: "Room 4", body: "Glue sticks, please.")

      expect(response).to have_http_status(:created)
      expect(church.feedbacks.sole).to have_attributes(sender_role: "staff", family: nil)
    end

    it "isn't open to an account that doesn't belong to the church" do
      stranger = create(:account)
      send_feedback(as: stranger)
      expect(response).to have_http_status(:forbidden)
      expect(church.feedbacks).to be_empty
    end

    it "rejects a bad file and saves nothing" do
      send_feedback(attachments: [upload("store-item.png"), upload("not-a.pdf", "application/pdf")])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("Attachments have to be pictures, PDF, Word, PowerPoint or Excel files.")
      expect(church.feedbacks).to be_empty
    end

    it "emails the church's admins and owners, not other members or the sender" do
      admin = create(:account, email: "admin@grace.example")
      owner = create(:account, email: "owner@grace.example")
      create(:membership, :admin, church: church, account: admin)
      create(:membership, :owner, church: church, account: owner)
      create(:membership, church: church, account: create(:account, email: "member@grace.example"))
      create(:membership, :admin, church: create(:church), account: create(:account, email: "elsewhere@example.com"))

      perform_enqueued_jobs { send_feedback }

      recipients = ActionMailer::Base.deliveries.flat_map(&:to)
      expect(recipients).to contain_exactly("admin@grace.example", "owner@grace.example")
    ensure
      ActionMailer::Base.deliveries.clear
    end
  end

  describe "GET /api/v1/feedback" do
    it "lists only this account's own submissions, newest first, with no attachment links" do
      create(:spirely_feedback, church: church, account: account, body: "Older", created_at: 2.days.ago)
      mine = create(:spirely_feedback, church: church, account: account, body: "Newer")
      mine.attach_files([upload("store-item.png")])
      create(:spirely_feedback, church: church, account: create(:account), body: "Someone else's")

      get "/api/v1/feedback", headers: auth_headers(account)

      expect(response).to have_http_status(:ok)
      expect(json["feedback"].map { |f| f["body"] }).to eq(%w[Newer Older])
      expect(json["feedback"].first["attachment_count"]).to eq(1)
      expect(json["feedback"].first).not_to have_key("attachments")
      expect(json["feedback"].first).not_to have_key("staff_note")
    end
  end

  describe "GET /api/v1/feedback/about_options" do
    it "offers the church's rooms" do
      create(:spirely_location, church: church, name: "Room 4")
      create(:spirely_location, church: church, name: "Nursery")
      create(:spirely_location, church: create(:church), name: "Not ours")

      get "/api/v1/feedback/about_options", headers: auth_headers(account)

      expect(json["rooms"]).to eq(["Nursery", "Room 4"])
      expect(json["events"]).to eq([])
    end
  end
end
