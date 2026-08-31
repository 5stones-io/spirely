require "rails_helper"

RSpec.describe Spirely::FamilyPost, type: :model do
  describe "validations" do
    it "is valid with required fields" do
      expect(build(:spirely_family_post)).to be_valid
    end

    it "requires a body" do
      expect(build(:spirely_family_post, body: "")).not_to be_valid
    end

    it "rejects a post_type outside the canonical set" do
      expect(build(:spirely_family_post, post_type: "rumor")).not_to be_valid
    end

    it "rejects an audience outside the canonical set" do
      expect(build(:spirely_family_post, audience: "everyone")).not_to be_valid
    end

    it "rejects a status outside the canonical set" do
      expect(build(:spirely_family_post, status: "archived")).not_to be_valid
    end

    it "rejects a child that belongs to a different family" do
      family      = create(:spirely_family)
      other_child = create(:spirely_child)
      post = build(:spirely_family_post, family: family, church: family.church, child: other_child)
      expect(post).not_to be_valid
      expect(post.errors[:child]).to be_present
    end

    it "accepts a child that belongs to the posting family" do
      family = create(:spirely_family)
      child  = create(:spirely_child, family: family)
      post = build(:spirely_family_post, family: family, church: family.church, child: child)
      expect(post).to be_valid
    end
  end

  describe "defaults" do
    it "defaults post_type to prayer_request" do
      expect(create(:spirely_family_post, post_type: nil).post_type).to eq("prayer_request")
    end

    it "defaults audience to church" do
      expect(create(:spirely_family_post, audience: nil).audience).to eq("church")
    end

    it "auto-approves when the church has moderation disabled" do
      church = create(:church, family_posts_moderation_enabled: false)
      post = create(:spirely_family_post, church: church, status: nil)
      expect(post.status).to eq("approved")
    end

    it "starts pending when the church has moderation enabled" do
      church = create(:church, family_posts_moderation_enabled: true)
      post = create(:spirely_family_post, church: church, status: nil)
      expect(post.status).to eq("pending")
    end

    it "leaves an explicitly-set status alone" do
      church = create(:church, family_posts_moderation_enabled: true)
      post = create(:spirely_family_post, church: church, status: "approved")
      expect(post.status).to eq("approved")
    end
  end

  describe "#approve!" do
    it "sets status, moderated_by, and moderated_at, and clears any rejected_reason" do
      membership = create(:membership, :admin)
      post = create(:spirely_family_post, status: "pending", rejected_reason: "duplicate")

      post.approve!(membership)

      expect(post.status).to eq("approved")
      expect(post.moderated_by).to eq(membership)
      expect(post.moderated_at).to be_present
      expect(post.rejected_reason).to be_nil
    end
  end

  describe "#reject!" do
    it "sets status, moderated_by, moderated_at, and the reason" do
      membership = create(:membership, :admin)
      post = create(:spirely_family_post, status: "pending")

      post.reject!(membership, reason: "Not appropriate for the church-wide feed")

      expect(post.status).to eq("rejected")
      expect(post.moderated_by).to eq(membership)
      expect(post.rejected_reason).to eq("Not appropriate for the church-wide feed")
    end
  end

  describe ".visible_church_wide" do
    it "includes only approved, church-audience posts" do
      church = create(:church)
      visible  = create(:spirely_family_post, church: church, status: "approved", audience: "church")
      create(:spirely_family_post, church: church, status: "pending", audience: "church")
      create(:spirely_family_post, church: church, status: "approved", audience: "staff_only")

      expect(church.family_posts.visible_church_wide).to contain_exactly(visible)
    end
  end
end
