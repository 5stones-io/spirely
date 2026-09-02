require "rails_helper"

RSpec.describe Spirely::StaffInvitation, type: :model do
  describe "#accept!" do
    it "grants an admin membership and copies the invited name onto a nameless account" do
      invitation = create(:spirely_staff_invitation, invited_first_name: "Pat")
      account    = create(:account, first_name: nil)

      invitation.accept!(account.id)

      expect(invitation.reload.accepted?).to be(true)
      membership = Membership.find_by(account_id: account.id, church_id: invitation.church_id)
      expect(membership.role).to eq("admin")
      expect(account.reload.first_name).to eq("Pat")
    end

    it "does not overwrite an account's existing name" do
      invitation = create(:spirely_staff_invitation, invited_first_name: "Pat")
      account    = create(:account, first_name: "Original")

      invitation.accept!(account.id)

      expect(account.reload.first_name).to eq("Original")
    end

    it "leaves an existing owner/admin membership role alone" do
      invitation = create(:spirely_staff_invitation)
      account    = create(:account)
      membership = create(:membership, :owner, account: account, church: invitation.church)

      invitation.accept!(account.id)

      expect(membership.reload.role).to eq("owner")
    end
  end
end
