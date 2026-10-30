require "rails_helper"

# Staff see and edit the tasks assigned to them; admins manage everyone's
# through /api/v1/admin/tasks.
RSpec.describe "My tasks", type: :request do
  let(:church)     { create(:church) }
  let(:events)     { church.time_categories.create!(code: "EVT", name: "Events") }
  let(:sam)        { create(:account, first_name: "Sam", last_name: "Ortiz") }
  let!(:sam_member) { create(:membership, church: church, account: sam, staff: true) }
  let(:jenna)      { create(:account) }
  let!(:jenna_member) { create(:membership, :admin, church: church, account: jenna) }

  before { use_tenant_host!(church) }

  def json = JSON.parse(response.body)

  def task_for(member, **attrs)
    create(:spirely_task, church: church, assignee_membership_id: member&.id, **attrs)
  end

  describe "GET /api/v1/my_tasks" do
    it "lists only the tasks assigned to them" do
      mine = task_for(sam_member, title: "Print name tags", due_date: Date.new(2026, 10, 31), time_category: events)
      task_for(jenna_member)
      task_for(nil)
      create(:spirely_task, church: create(:church), assignee_membership_id: sam_member.id)

      get "/api/v1/my_tasks", headers: auth_headers(sam)

      expect(response).to have_http_status(:ok)
      expect(json["tasks"].sole).to include("id" => mine.id, "title" => "Print name tags", "due_date" => "2026-10-31",
                                            "status" => "not_started")
      expect(json["tasks"].sole["time_category"]).to include("code" => "EVT")
      expect(json["tasks"].sole["assignee"]).to include("id" => sam_member.id, "name" => "Sam Ortiz")
    end

    it "filters by status" do
      open = task_for(sam_member)
      task_for(sam_member, status: "complete")

      get "/api/v1/my_tasks", params: { status: "not_started" }, headers: auth_headers(sam)

      expect(json["tasks"].map { |t| t["id"] }).to eq([open.id])
    end

    it "shows an admin only their own tasks too" do
      theirs = task_for(jenna_member)
      task_for(sam_member)

      get "/api/v1/my_tasks", headers: auth_headers(jenna)

      expect(json["tasks"].map { |t| t["id"] }).to eq([theirs.id])
    end

    it "is for staff, not families" do
      parent = create(:account)
      create(:membership, church: church, account: parent, role: "family")

      get "/api/v1/my_tasks", headers: auth_headers(parent)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/my_tasks/:id" do
    it "shows one of their tasks" do
      task = task_for(sam_member, description: "Two per kid")
      get "/api/v1/my_tasks/#{task.id}", headers: auth_headers(sam)
      expect(json).to include("id" => task.id, "description" => "Two per kid")
    end

    it "doesn't show someone else's" do
      task = task_for(jenna_member)
      get "/api/v1/my_tasks/#{task.id}", headers: auth_headers(sam)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/my_tasks/:id" do
    it "updates the status and details of their task" do
      task = task_for(sam_member)

      patch "/api/v1/my_tasks/#{task.id}",
            params: { task: { status: "in_progress", title: "Print name tags", description: "Two per kid",
                              due_date: "2026-11-02", time_category_id: events.id } },
            headers: auth_headers(sam), as: :json

      expect(response).to have_http_status(:ok)
      expect(json).to include("status" => "in_progress", "title" => "Print name tags", "description" => "Two per kid",
                              "due_date" => "2026-11-02")
      expect(task.reload.time_category).to eq(events)
    end

    it "marks a task done" do
      task = task_for(sam_member)
      patch "/api/v1/my_tasks/#{task.id}", params: { task: { status: "complete" } }, headers: auth_headers(sam), as: :json
      expect(json["completed_at"]).to be_present
    end

    it "adds the next one when a task that repeats from completion is done" do
      task = task_for(sam_member, recurrence_rule: "weekly", recurrence_mode: "relative")
      expect {
        patch "/api/v1/my_tasks/#{task.id}", params: { task: { status: "complete" } }, headers: auth_headers(sam), as: :json
      }.to change(Spirely::Task, :count).by(1)
    end

    it "can't hand the task to someone else or change how it repeats" do
      task = task_for(sam_member)

      patch "/api/v1/my_tasks/#{task.id}",
            params: { task: { assignee_membership_id: jenna_member.id, recurrence_rule: "daily", recurrence_mode: "absolute",
                              status: "in_progress" } },
            headers: auth_headers(sam), as: :json

      task.reload
      expect(task.assignee_membership_id).to eq(sam_member.id)
      expect(task.recurrence_rule).to eq("none")
      expect(task.status).to eq("in_progress")
    end

    it "can't edit someone else's task" do
      task = task_for(jenna_member)
      patch "/api/v1/my_tasks/#{task.id}", params: { task: { status: "complete" } }, headers: auth_headers(sam), as: :json
      expect(response).to have_http_status(:not_found)
      expect(task.reload.status).to eq("not_started")
    end

    it "refuses another church's category" do
      task = task_for(sam_member)
      other = create(:church).time_categories.create!(code: "X", name: "Elsewhere")
      patch "/api/v1/my_tasks/#{task.id}", params: { task: { time_category_id: other.id } }, headers: auth_headers(sam), as: :json
      expect(response).to have_http_status(:not_found)
      expect(task.reload.time_category).to be_nil
    end

    it "explains an invalid change" do
      task = task_for(sam_member)
      patch "/api/v1/my_tasks/#{task.id}", params: { task: { title: "" } }, headers: auth_headers(sam), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["code"]).to eq("validation_error")
    end
  end
end
