require "rails_helper"

RSpec.describe "Admin Tasks API", type: :request do
  describe "GET /api/v1/admin/tasks" do
    it "requires admin" do
      church  = create(:church)
      account = create(:account)
      create(:membership, church: church, account: account, role: "family")

      use_tenant_host!(church)
      get "/api/v1/admin/tasks", headers: auth_headers(account)
      expect(response).to have_http_status(:forbidden)
    end

    it "lists tasks for this church, scoped from other churches" do
      church       = create(:church)
      other_church = create(:church)
      admin        = create(:account)
      create(:membership, :admin, church: church, account: admin)

      task = create(:spirely_task, church: church)
      create(:spirely_task, church: other_church)

      use_tenant_host!(church)
      get "/api/v1/admin/tasks", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)

      ids = JSON.parse(response.body)["tasks"].map { |t| t["id"] }
      expect(ids).to eq([task.id])
    end

    it "filters by status" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)

      done = create(:spirely_task, church: church, status: "complete")
      create(:spirely_task, church: church, status: "not_started")

      use_tenant_host!(church)
      get "/api/v1/admin/tasks", params: { status: "complete" }, headers: auth_headers(admin)
      ids = JSON.parse(response.body)["tasks"].map { |t| t["id"] }
      expect(ids).to eq([done.id])
    end

    it "includes the assignee's email when assigned" do
      church        = create(:church)
      admin         = create(:account)
      admin_member  = create(:membership, :admin, church: church, account: admin)
      assignee_acct = create(:account, email: "staffer@example.com")
      assignee      = create(:membership, :admin, church: church, account: assignee_acct)
      create(:spirely_task, church: church, assignee: assignee, created_by: admin_member)

      use_tenant_host!(church)
      get "/api/v1/admin/tasks", headers: auth_headers(admin)
      body = JSON.parse(response.body)["tasks"].first
      expect(body["assignee"]["email"]).to eq("staffer@example.com")
    end
  end

  describe "GET /api/v1/admin/tasks/:id" do
    it "404s for a task belonging to another church" do
      church       = create(:church)
      other_church = create(:church)
      admin        = create(:account)
      create(:membership, :admin, church: church, account: admin)
      other_task = create(:spirely_task, church: other_church)

      use_tenant_host!(church)
      get "/api/v1/admin/tasks/#{other_task.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/admin/tasks" do
    it "creates a task, stamping created_by from the current membership" do
      church       = create(:church)
      admin        = create(:account)
      admin_member = create(:membership, :admin, church: church, account: admin)

      use_tenant_host!(church)
      post "/api/v1/admin/tasks",
           params: { task: { title: "Order VBS supplies", status: "in_progress" } },
           headers: auth_headers(admin)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["title"]).to eq("Order VBS supplies")
      expect(body["status"]).to eq("in_progress")
      expect(body["created_by"]["id"]).to eq(admin_member.id)
    end

    it "requires a title" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)

      use_tenant_host!(church)
      post "/api/v1/admin/tasks", params: { task: { title: "" } }, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["code"]).to eq("validation_error")
    end
  end

  describe "PATCH /api/v1/admin/tasks/:id" do
    it "updates status" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)
      task = create(:spirely_task, church: church, status: "not_started")

      use_tenant_host!(church)
      patch "/api/v1/admin/tasks/#{task.id}", params: { task: { status: "complete" } }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(task.reload.status).to eq("complete")
    end

    it "sets a recurrence rule" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)
      task = create(:spirely_task, church: church)

      use_tenant_host!(church)
      patch "/api/v1/admin/tasks/#{task.id}",
            params: { task: { recurrence_rule: "every_n_days", recurrence_mode: "relative", recurrence_interval: 3 } },
            headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["recurrence_rule"]).to eq("every_n_days")
      expect(body["recurrence_mode"]).to eq("relative")
      expect(body["recurrence_interval"]).to eq(3)
    end

    it "generates the next occurrence when a relative-recurrence task is marked complete" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)
      task = create(:spirely_task, church: church, recurrence_rule: "weekly", recurrence_mode: "relative", status: "not_started")

      use_tenant_host!(church)
      expect {
        patch "/api/v1/admin/tasks/#{task.id}", params: { task: { status: "complete" } }, headers: auth_headers(admin)
      }.to change(Spirely::Task, :count).by(1)
      expect(response).to have_http_status(:ok)
    end

    it "does not generate a next occurrence when an absolute-recurrence task is marked complete" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)
      task = create(:spirely_task, church: church, recurrence_rule: "weekly", recurrence_mode: "absolute",
                                    due_date: 1.week.from_now.to_date, status: "not_started")

      use_tenant_host!(church)
      expect {
        patch "/api/v1/admin/tasks/#{task.id}", params: { task: { status: "complete" } }, headers: auth_headers(admin)
      }.not_to change(Spirely::Task, :count)
    end

    it "does not regenerate on an unrelated update to an already-complete recurring task" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)
      task = create(:spirely_task, church: church, recurrence_rule: "weekly", recurrence_mode: "relative", status: "complete")

      use_tenant_host!(church)
      expect {
        patch "/api/v1/admin/tasks/#{task.id}", params: { task: { description: "note" } }, headers: auth_headers(admin)
      }.not_to change(Spirely::Task, :count)
    end

    it "reassigns to a different staff membership" do
      church        = create(:church)
      admin         = create(:account)
      create(:membership, :admin, church: church, account: admin)
      assignee_acct = create(:account)
      assignee      = create(:membership, :admin, church: church, account: assignee_acct)
      task = create(:spirely_task, church: church)

      use_tenant_host!(church)
      patch "/api/v1/admin/tasks/#{task.id}",
            params: { task: { assignee_membership_id: assignee.id } },
            headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(task.reload.assignee_membership_id).to eq(assignee.id)
    end
  end

  describe "DELETE /api/v1/admin/tasks/:id" do
    it "destroys the task" do
      church = create(:church)
      admin  = create(:account)
      create(:membership, :admin, church: church, account: admin)
      task = create(:spirely_task, church: church)

      use_tenant_host!(church)
      delete "/api/v1/admin/tasks/#{task.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:no_content)
      expect(Spirely::Task.exists?(task.id)).to eq(false)
    end
  end
end
