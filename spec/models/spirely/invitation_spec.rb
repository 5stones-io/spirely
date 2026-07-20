require "rails_helper"

RSpec.describe Spirely::Invitation, type: :model do
  it "generates a token and expiry on create" do
    invitation = create(:spirely_invitation)
    expect(invitation.token).to be_present
    expect(invitation.expires_at).to be_within(1.minute).of(7.days.from_now)
  end

  describe ".find_active" do
    it "finds an unexpired, unaccepted invitation by token" do
      invitation = create(:spirely_invitation)
      expect(described_class.find_active(invitation.token)).to eq(invitation)
    end

    it "returns nil for an expired invitation" do
      invitation = create(:spirely_invitation)
      invitation.update_column(:expires_at, 1.day.ago) # generate_token forces expires_at on create
      expect(described_class.find_active(invitation.token)).to be_nil
    end

    it "returns nil for an already-accepted invitation" do
      invitation = create(:spirely_invitation, accepted_at: Time.current)
      expect(described_class.find_active(invitation.token)).to be_nil
    end
  end

  describe "#accept!" do
    it "links the family to the given account and marks accepted" do
      invitation = create(:spirely_invitation)
      account    = create(:account)

      invitation.accept!(account.id)

      expect(invitation.reload.accepted?).to be(true)
      expect(invitation.family.reload.account_id).to eq(account.id)
    end
  end
end
