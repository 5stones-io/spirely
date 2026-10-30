require "rails_helper"

RSpec.describe Spirely::Invitation, type: :model do
  it "generates a token, expiry, and inherits church_id from its family on create" do
    invitation = create(:spirely_invitation)
    expect(invitation.token).to be_present
    expect(invitation.expires_at).to be_within(1.minute).of(7.days.from_now)
    expect(invitation.church_id).to eq(invitation.family.church_id)
  end

  describe ".find_active" do
    it "finds an unexpired, unaccepted invitation by token" do
      invitation = create(:spirely_invitation)
      expect(described_class.find_active(invitation.token)).to eq(invitation)
    end

    it "returns nil for an expired invitation" do
      invitation = create(:spirely_invitation)
      invitation.update_column(:expires_at, 1.day.ago)
      expect(described_class.find_active(invitation.token)).to be_nil
    end

    it "returns nil for an already-accepted invitation" do
      invitation = create(:spirely_invitation, accepted_at: Time.current)
      expect(described_class.find_active(invitation.token)).to be_nil
    end
  end

  describe "#accept!" do
    it "links the family to the given account and creates a family-role Membership" do
      invitation = create(:spirely_invitation)
      account    = create(:account)

      invitation.accept!(account.id)

      expect(invitation.reload.accepted?).to be(true)
      expect(invitation.family.reload.account_id).to eq(account.id)

      membership = Membership.find_by(account: account, church: invitation.church)
      expect(membership).to be_present
      expect(membership.role).to eq("family")
    end

    it "reuses an existing Membership rather than erroring if one already exists" do
      invitation = create(:spirely_invitation)
      account    = create(:account)
      create(:membership, account: account, church: invitation.church, role: "admin")

      expect { invitation.accept!(account.id) }.not_to raise_error
      expect(Membership.where(account: account, church: invitation.church).count).to eq(1)
    end

    describe "when guardian-scoped (multi-account family access)" do
      it "links the account to the Guardian, not the Family, and still creates the Membership" do
        family     = create(:spirely_family, account: nil)
        guardian   = create(:spirely_guardian, family: family)
        invitation = create(:spirely_invitation, family: family, guardian: guardian)
        account    = create(:account)

        invitation.accept!(account.id)

        expect(invitation.reload.accepted?).to be(true)
        expect(guardian.reload.account_id).to eq(account.id)
        expect(family.reload.account_id).to be_nil

        membership = Membership.find_by(account: account, church: family.church)
        expect(membership).to be_present
        expect(membership.role).to eq("family")
      end

      it "lets a second account claim a different guardian on the same family the primary contact already claimed" do
        family      = create(:spirely_family, account: nil)
        guardian    = create(:spirely_guardian, family: family)
        primary_inv = create(:spirely_invitation, family: family)
        guardian_inv = create(:spirely_invitation, family: family, guardian: guardian)
        primary_account  = create(:account)
        guardian_account = create(:account)

        primary_inv.accept!(primary_account.id)
        guardian_inv.accept!(guardian_account.id)

        expect(family.reload.account_id).to eq(primary_account.id)
        expect(guardian.reload.account_id).to eq(guardian_account.id)
      end
    end
  end
end
