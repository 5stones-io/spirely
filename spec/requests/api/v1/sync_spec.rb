require "rails_helper"

RSpec.describe "POST /api/v1/sync/trigger", type: :request do
  include ActiveJob::TestHelper

  # The gem's test env uses the :async adapter; the job matchers need :test.
  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  before { Spirely.configuration.encryption_key = SecureRandom.hex(32) }

  def admin_for(church)
    account = create(:account)
    create(:membership, :admin, church: church, account: account)
    account
  end

  def trigger(church)
    create(:spirely_church_integration, church: church, access_token: "token")
    use_tenant_host!(church)
    post "/api/v1/sync/trigger", headers: auth_headers(admin_for(church))
    JSON.parse(response.body)["enqueued"]
  end

  it "queues the groups sync when a groups module is on" do
    church = create(:church, enabled_modules: ["smallgroups"])
    expect { expect(trigger(church)).to include("groups") }
      .to have_enqueued_job(Spirely::PcoGroupsSyncJob).with(church.id)
  end

  it "doesn't queue it otherwise" do
    church = create(:church, enabled_modules: ["kidsmin"])
    expect(trigger(church)).not_to include("groups")
    expect(Spirely::PcoGroupsSyncJob).not_to have_been_enqueued
  end
end
