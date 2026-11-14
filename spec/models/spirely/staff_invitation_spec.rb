require "rails_helper"

RSpec.describe Spirely::StaffInvitation, type: :model do
  it "generates a unique token and a 7-day expiry on create" do
    invitation = create(:spirely_staff_invitation)

    expect(invitation.token).to be_present
    expect(invitation.expires_at).to be_within(1.minute).of(7.days.from_now)
  end

  it "requires an email or phone" do
    invitation = build(:spirely_staff_invitation, invited_email: nil, invited_phone: nil)

    expect(invitation).not_to be_valid
    expect(invitation.errors[:base]).to include("An email or phone number is required")
  end

  it "is valid with only a phone and no email" do
    invitation = build(:spirely_staff_invitation, invited_email: nil, invited_phone: "555-0100")

    expect(invitation).to be_valid
  end

  describe "#accept!" do
    it "grants an admin membership and copies the invited name onto a nameless account" do
      invitation = create(:spirely_staff_invitation, invited_first_name: "Pat", invited_last_name: "Smith")
      account    = create(:account, first_name: nil, last_name: nil)

      invitation.accept!(account.id)

      expect(invitation.reload.accepted?).to be(true)
      membership = Membership.find_by(account_id: account.id, church_id: invitation.church_id)
      expect(membership.role).to eq("admin")
      expect(account.reload.first_name).to eq("Pat")
      expect(account.last_name).to eq("Smith")
    end

    it "does not overwrite an account's existing name" do
      invitation = create(:spirely_staff_invitation, invited_first_name: "Pat", invited_last_name: "Smith")
      account    = create(:account, first_name: "Original", last_name: "Name")

      invitation.accept!(account.id)

      expect(account.reload.first_name).to eq("Original")
      expect(account.last_name).to eq("Name")
    end

    it "is idempotent if a Membership already exists for that account/church" do
      church     = create(:church)
      invitation = create(:spirely_staff_invitation, church: church)
      account    = create(:account)
      create(:membership, account: account, church: church, role: "admin")

      expect { invitation.accept!(account.id) }.not_to raise_error
    end

    it "upgrades an existing lesser-role Membership to admin — real production bug (Danielle Robinett, a parent/volunteer being invited onto staff)" do
      church     = create(:church)
      invitation = create(:spirely_staff_invitation, church: church)
      account    = create(:account)
      create(:membership, account: account, church: church, role: "family")

      invitation.accept!(account.id)

      membership = Membership.find_by(account: account, church: church)
      expect(membership.role).to eq("admin")
      expect(Membership.where(account: account, church: church).count).to eq(1)
    end

    it "does not downgrade an existing owner Membership to admin" do
      church     = create(:church)
      invitation = create(:spirely_staff_invitation, church: church)
      account    = create(:account)
      create(:membership, account: account, church: church, role: "owner")

      invitation.accept!(account.id)

      membership = Membership.find_by(account: account, church: church)
      expect(membership.role).to eq("owner")
    end
  end

  describe ".find_active" do
    it "does not find an expired invitation" do
      invitation = create(:spirely_staff_invitation, expires_at: 1.day.ago)

      expect(Spirely::StaffInvitation.find_active(invitation.token)).to be_nil
    end

    it "does not find an already-accepted invitation" do
      invitation = create(:spirely_staff_invitation, accepted_at: Time.current)

      expect(Spirely::StaffInvitation.find_active(invitation.token)).to be_nil
    end

    it "finds a still-active invitation by token" do
      invitation = create(:spirely_staff_invitation)

      expect(Spirely::StaffInvitation.find_active(invitation.token)).to eq(invitation)
    end
  end
end
