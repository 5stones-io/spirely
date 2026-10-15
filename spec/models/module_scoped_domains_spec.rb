require "rails_helper"

# Module-scoped custom domains (5ST-12): a church's domain can narrow which
# modules it shows and carry its own branding.
RSpec.describe "Module-scoped custom domains", type: :model do
  let(:church) { create(:church, enabled_modules: %w[kidsmin smallgroups], display_name: "JCC Kidz") }
  let!(:kids)   { create(:custom_domain, :verified, church: church, hostname: "kidz.example.org", primary: true, modules: %w[kidsmin]) }
  let!(:portal) { create(:custom_domain, :verified, church: church, hostname: "portal.example.org", modules: %w[smallgroups], display_name: "Jubilee Christian Center") }

  after { Current.reset }

  describe "#active_modules" do
    it "is every enabled module outside a request" do
      expect(church.active_modules).to eq(%w[kidsmin smallgroups])
      expect(church.uses_groups?).to be true
    end

    it "narrows to the request's domain" do
      Current.custom_domain = portal
      expect(church.active_modules).to eq(%w[smallgroups])
      expect(church.module_enabled?("kidsmin")).to be false

      Current.custom_domain = kids
      expect(church.active_modules).to eq(%w[kidsmin smallgroups])
    end

    it "gives a kids-only domain Small Groups only when the church has it on" do
      Current.custom_domain = kids
      expect(church.children_groups_only?).to be true

      church.update!(enabled_modules: %w[kidsmin])
      expect(church.active_modules).to eq(%w[kidsmin])
      expect(church.uses_groups?).to be false
    end

    it "never turns on a module the church has off" do
      church.update!(enabled_modules: %w[kidsmin])
      Current.custom_domain = portal
      expect(church.active_modules).to eq([])
    end

    it "ignores another church's domain" do
      Current.custom_domain = create(:custom_domain, :verified, modules: %w[kidsmin])
      expect(church.active_modules).to eq(%w[kidsmin smallgroups])
    end

    it "treats a domain with no modules as unrestricted" do
      Current.custom_domain = create(:custom_domain, :verified, church: church)
      expect(church.active_modules).to eq(%w[kidsmin smallgroups])
    end
  end

  describe "#visible_groups" do
    let(:kids_type) { church.group_types.create!(name: "Kids", pco_group_type_id: "gt-k", audience: "children") }
    let!(:rangers)  { church.groups.create!(name: "Rangers", pco_group_id: "g1", group_type: kids_type) }
    let!(:moms)     { church.groups.create!(name: "Moms", pco_group_id: "g2") }

    it "is every group outside a request and on an unrestricted or Small Groups domain" do
      expect(church.visible_groups).to contain_exactly(rangers, moms)
      Current.custom_domain = portal
      expect(church.children_groups_only?).to be false
      expect(church.visible_groups).to contain_exactly(rangers, moms)
    end

    it "is only children's groups on a kids-only domain" do
      Current.custom_domain = kids
      expect(church.visible_groups).to contain_exactly(rangers)
    end
  end

  describe "#hostname_for_module" do
    it "prefers the domain scoped to that module" do
      expect(church.hostname_for_module("smallgroups")).to eq("portal.example.org")
      expect(church.hostname_for_module("kidsmin")).to eq("kidz.example.org")
    end

    it "skips a primary domain that doesn't serve the module" do
      portal.destroy!
      expect(church.reload.hostname_for_module("smallgroups")).to eq(church.default_hostname)
    end

    it "uses an unrestricted domain when no scoped one matches" do
      portal.destroy!
      create(:custom_domain, :verified, church: church, hostname: "app.example.org")
      expect(church.reload.hostname_for_module("smallgroups")).to eq("app.example.org")
    end

    it "ignores unverified domains" do
      portal.update!(verified_at: nil)
      expect(church.reload.hostname_for_module("smallgroups")).to eq(church.default_hostname)
    end
  end

  describe "branding" do
    it "uses the domain's own name and only its own logo" do
      church.logo.attach(io: StringIO.new("<svg/>"), filename: "kids.svg", content_type: "image/svg+xml")
      expect(church.brand_name).to eq("JCC Kidz")
      expect(church.active_logo).to be_present

      Current.custom_domain = portal
      expect(church.brand_name).to eq("Jubilee Christian Center")
      expect(church.active_logo).to be_nil

      portal.logo.attach(io: StringIO.new("<svg/>"), filename: "portal.svg", content_type: "image/svg+xml")
      expect(church.active_logo.blob.filename.to_s).to eq("portal.svg")
    end

    it "keeps the church's branding on a domain without its own" do
      Current.custom_domain = kids
      expect(church.brand_name).to eq("JCC Kidz")
    end
  end

  it "rejects unknown modules" do
    domain = build(:custom_domain, church: church, modules: %w[nope])
    expect(domain).not_to be_valid
  end
end
