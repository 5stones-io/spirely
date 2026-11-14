require "rails_helper"

# 5ST-79 follow-up: a "Pastors only" audience, and prayer requests that
# drop off other families' pages 30 days after they were posted or renewed.
RSpec.describe Spirely::FamilyPost, "pastors only and expiry", type: :model do
  let(:church) { create(:church) }
  let(:family) { create(:spirely_family, church: church) }
  let(:other_family) { create(:spirely_family, church: church) }

  def prayer(**attrs)
    create(:spirely_family_post, church: church, family: family, post_type: "prayer_request", **attrs)
  end

  describe "pastors only" do
    it "skips moderation, even when the church reviews posts" do
      church.update!(family_posts_moderation_enabled: true)
      expect(prayer(audience: "pastors_only").status).to eq("approved")
      expect(prayer(audience: "church").status).to eq("pending")
    end

    it "is only for prayer requests and praise reports" do
      post_ = build(:spirely_family_post, church: church, family: family, post_type: "milestone", audience: "pastors_only")
      expect(post_).not_to be_valid
      expect(build(:spirely_family_post, church: church, family: family, post_type: "praise_report", audience: "pastors_only")).to be_valid
    end

    it "goes back to review when its family shares it more widely" do
      church.update!(family_posts_moderation_enabled: true)
      post_ = prayer(audience: "pastors_only")
      post_.update!(audience: "church")
      expect(post_.status).to eq("pending")
    end

    it "is hidden from staff who aren't pastors" do
      shared = prayer(audience: "pastors_only")
      plain  = prayer(audience: "staff_only")
      admin  = create(:membership, :admin, church: church)
      pastor = create(:membership, church: church, pastor: true)

      expect(church.family_posts.visible_to_staff(admin)).to contain_exactly(plain)
      expect(church.family_posts.visible_to_staff(pastor)).to contain_exactly(shared, plain)
    end

    it "never shows in another family's feed" do
      shared = prayer(audience: "pastors_only")
      expect(church.family_posts.visible_to_family(other_family)).not_to include(shared)
      expect(church.family_posts.visible_to_family(family)).to include(shared)
    end
  end

  describe "expiry" do
    it "expires an unanswered prayer request 30 days after it was posted or renewed" do
      fresh = prayer(created_at: 29.days.ago)
      old   = prayer(created_at: 31.days.ago)
      renewed = prayer(created_at: 40.days.ago, renewed_at: 2.days.ago)
      answered = prayer(created_at: 40.days.ago, answered_at: 35.days.ago)
      praise = create(:spirely_family_post, church: church, family: family, post_type: "praise_report", created_at: 40.days.ago)

      expect([fresh, old, renewed, answered, praise].map(&:expired?)).to eq([false, true, false, false, false])
      expect(old.expires_at).to be_within(1.second).of(old.created_at + 30.days)
    end

    it "takes expired requests off other families' feeds, but not the poster's" do
      old = prayer(created_at: 31.days.ago)
      expect(church.family_posts.visible_to_family(other_family)).not_to include(old)
      expect(church.family_posts.visible_to_family(family)).to include(old)
    end

    it "keeps expired requests for staff" do
      old = prayer(created_at: 31.days.ago)
      expect(church.family_posts.visible_to_staff(create(:membership, :admin, church: church))).to include(old)
    end

    describe "#renew!" do
      it "starts another 30 days" do
        old = prayer(created_at: 31.days.ago)
        old.renew!
        expect(old.expired?).to be(false)
        expect(church.family_posts.visible_to_family(other_family)).to include(old)
      end

      it "is only for unanswered prayer requests" do
        praise = create(:spirely_family_post, church: church, family: family, post_type: "praise_report")
        expect { praise.renew! }.to raise_error(Spirely::FamilyPost::PrayerError)
        expect { prayer(answered_at: 1.day.ago).renew! }.to raise_error(Spirely::FamilyPost::PrayerError)
      end
    end
  end
end
