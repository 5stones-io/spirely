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
end
