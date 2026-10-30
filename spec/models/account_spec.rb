require "rails_helper"

RSpec.describe Account, type: :model do
  describe "#name" do
    it "joins first and last name" do
      account = build(:account, first_name: "Pat", last_name: "Smith")
      expect(account.name).to eq("Pat Smith")
    end

    it "is nil when no name is set, so callers can fall back to email" do
      account = build(:account, first_name: nil, last_name: nil)
      expect(account.name).to be_nil
    end

    it "handles a first name with no last name" do
      account = build(:account, first_name: "Pat", last_name: nil)
      expect(account.name).to eq("Pat")
    end
  end

  describe "email normalization" do
    it "downcases and strips email on save" do
      account = create(:account, email: "  Jane.Doe@Example.COM  ")
      expect(account.reload.email).to eq("jane.doe@example.com")
    end

    # This callback alone does NOT make find_or_create_by! itself
    # case-insensitive — its find_by runs before any callback does. Real
    # protection is downcasing at each call site before searching
    # (ChurchProvisioner, Rodauth's account_from_login,
    # Bridge::LoginController#callback) — confirmed necessary by a real
    # duplicate found in production (two Account rows differing only by
    # case, from before this fix). This spec documents that a *caller*
    # who downcases first — as all three real call sites now do — gets
    # the existing row rather than creating a duplicate.
    it "lets a caller who downcases first find an existing differently-cased row" do
      existing = create(:account, email: "Mixed@Example.com") # saved as mixed@example.com
      found = Account.find_or_create_by!(email: "Mixed@Example.com".downcase)
      expect(found).to eq(existing)
      expect(Account.where("lower(email) = ?", "mixed@example.com").count).to eq(1)
    end
  end
end
