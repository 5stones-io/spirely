require "rails_helper"

RSpec.describe Membership, type: :model do
  it "is valid with a known role" do
    expect(build(:membership, role: "admin")).to be_valid
  end

  it "rejects an unknown role" do
    expect(build(:membership, role: "superuser")).not_to be_valid
  end

  it "prevents duplicate memberships for the same account+church" do
    membership = create(:membership)
    duplicate  = build(:membership, account: membership.account, church: membership.church)
    expect(duplicate).not_to be_valid
  end

  it "allows the same account to have memberships at different churches" do
    account = create(:account)
    create(:membership, account: account, church: create(:church))
    second  = build(:membership, account: account, church: create(:church))
    expect(second).to be_valid
  end

  describe "#admin_or_owner?" do
    it "is true for admin and owner roles" do
      expect(build(:membership, role: "admin").admin_or_owner?).to be(true)
      expect(build(:membership, role: "owner").admin_or_owner?).to be(true)
    end

    it "is false for family role" do
      expect(build(:membership, role: "family").admin_or_owner?).to be(false)
    end
  end
end
