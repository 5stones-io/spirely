require "rails_helper"

# Staff inbox for feedback and requests (5ST-80): admins and owners only.
RSpec.describe "Admin feedback API", type: :request do
  let(:church) { create(:church) }
  let(:admin)  { create(:account, first_name: "Sam", last_name: "Ortiz") }
  let(:parent) { create(:account, first_name: "Megan", last_name: "Torres") }
  let!(:family) { create(:spirely_family, church: church, account: parent, family_name: "Torres") }

  before do
    create(:membership, :admin, church: church, account: admin)
    use_tenant_host!(church)
  end

  def json = JSON.parse(response.body)
  def path_of(url) = URI(url).path

  def upload(name)
    fixture_file_upload(name, "application/octet-stream")
  end

  def feedback_from_parent(**attrs)
    create(:spirely_feedback, { church: church, account: parent, family: family, sender_role: "parent" }.merge(attrs))
  end

  describe "GET /api/v1/admin/feedback" do
    it "lists every submission with counts by status, and filters by status and category" do
      feedback_from_parent(category: "reflection", status: "new")
      feedback_from_parent(category: "supplies", status: "new")
      feedback_from_parent(category: "supplies", status: "in_progress")
      feedback_from_parent(category: "general", status: "done")
      create(:spirely_feedback, church: create(:church))

      get "/api/v1/admin/feedback", headers: auth_headers(admin)
      expect(json["feedback"].size).to eq(4)
      expect(json["counts"]).to eq("all" => 4, "new" => 2, "in_progress" => 1, "done" => 1)
      expect(json["feedback"].first["sender"]).to include("name" => "Megan Torres", "role" => "parent", "family_name" => "Torres")

      get "/api/v1/admin/feedback?status=new&category=supplies", headers: auth_headers(admin)
      expect(json["feedback"].size).to eq(1)
      # Counts are within the category picked.
      expect(json["counts"]).to eq("all" => 2, "new" => 1, "in_progress" => 1, "done" => 0)
    end

    it "is only for admins and owners" do
      staff = create(:account)
      create(:membership, church: church, account: staff, staff: true)

      get "/api/v1/admin/feedback", headers: auth_headers(staff)
      expect(response).to have_http_status(:forbidden)
      get "/api/v1/admin/feedback", headers: auth_headers(parent)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/admin/feedback/:id" do
    it "shows pictures inline and documents as downloads, through links that expire" do
      feedback = feedback_from_parent
      feedback.attach_files([upload("store-item.png"), upload("supply-list.pdf")])

      get "/api/v1/admin/feedback/#{feedback.id}", headers: auth_headers(admin)

      picture, document = json["attachments"]
      expect(picture).to include("filename" => "store-item.png", "kind" => "picture", "content_type" => "image/png")
      expect(document).to include("filename" => "supply-list.pdf", "kind" => "document", "content_type" => "application/pdf")

      get path_of(picture["url"])
      expect(response).to have_http_status(:found)
      get path_of(response.location)
      expect(response.headers["Content-Disposition"]).to start_with("inline")

      get path_of(document["url"])
      expect(response).to have_http_status(:found)
      get path_of(response.location)
      expect(response.headers["Content-Disposition"]).to start_with("attachment")

      travel 16.minutes do
        get path_of(document["url"])
        expect(response).to have_http_status(:not_found)
      end
    end

    it "won't open an attachment with a token minted for something else" do
      feedback = feedback_from_parent
      feedback.attach_files([upload("store-item.png")])
      blob = feedback.attachments.first.blob

      get "/api/v1/feedback_attachments/#{blob.signed_id(purpose: 'family_post_photo')}"
      expect(response).to have_http_status(:not_found)
    end

    it "can't see another church's feedback" do
      other = create(:spirely_feedback, church: create(:church))
      get "/api/v1/admin/feedback/#{other.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/admin/feedback/:id" do
    it "changes the status and the staff note, which the sender never sees" do
      feedback = feedback_from_parent

      patch "/api/v1/admin/feedback/#{feedback.id}",
            params: { feedback: { status: "in_progress", staff_note: "Added candy to next year's budget." } },
            headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(json).to include("status" => "in_progress", "staff_note" => "Added candy to next year's budget.")

      get "/api/v1/feedback", headers: auth_headers(parent)
      expect(json["feedback"].sole).to include("status" => "in_progress")
      expect(json["feedback"].sole).not_to have_key("staff_note")
    end

    it "won't take an unknown status" do
      feedback = feedback_from_parent
      patch "/api/v1/admin/feedback/#{feedback.id}", params: { feedback: { status: "archived" } }, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "making a task from feedback (POST /api/v1/admin/tasks with feedback_id)" do
    let(:category) { church.time_categories.create!(code: "FAC", name: "Facilities") }

    it "links the new task to the feedback and moves new feedback to in progress" do
      feedback = feedback_from_parent(category: "supplies", body: "Room 4 needs glue sticks.")

      post "/api/v1/admin/tasks",
           params: { task: { title: "Buy glue sticks for Room 4", description: "Room 4 needs glue sticks.",
                             time_category_id: category.id, feedback_id: feedback.id } },
           headers: auth_headers(admin)

      expect(response).to have_http_status(:created)
      task = church.tasks.sole
      expect(feedback.reload).to have_attributes(task: task, status: "in_progress")

      get "/api/v1/admin/feedback/#{feedback.id}", headers: auth_headers(admin)
      expect(json["task"]).to include("id" => task.id, "title" => "Buy glue sticks for Room 4", "status" => "not_started")
    end

    it "leaves done feedback done" do
      feedback = feedback_from_parent(status: "done")
      post "/api/v1/admin/tasks",
           params: { task: { title: "Follow up", time_category_id: category.id, feedback_id: feedback.id } },
           headers: auth_headers(admin)
      expect(feedback.reload).to have_attributes(status: "done", task: church.tasks.sole)
    end

    it "ignores another church's feedback id" do
      other = create(:spirely_feedback, church: create(:church))
      post "/api/v1/admin/tasks",
           params: { task: { title: "Sneaky", time_category_id: category.id, feedback_id: other.id } },
           headers: auth_headers(admin)
      expect(response).to have_http_status(:not_found)
      expect(church.tasks).to be_empty
    end
  end
end
