require "rails_helper"

RSpec.describe Church do
  describe "validations" do
    it "requires a valid slug format" do
      expect(build(:church, slug: "Invalid Slug!")).not_to be_valid
      expect(build(:church, slug: "valid-slug-123")).to be_valid
    end

    it "requires a unique slug" do
      create(:church, slug: "dupe")
      expect(build(:church, slug: "dupe")).not_to be_valid
    end
  end

  describe "#module_enabled?" do
    it "returns false for a module not in enabled_modules" do
      church = build(:church, enabled_modules: [])
      expect(church.module_enabled?("kidsmin")).to be(false)
    end

    it "returns true once a module is enabled" do
      church = build(:church, enabled_modules: ["kidsmin"])
      expect(church.module_enabled?("kidsmin")).to be(true)
    end
  end

  describe "#brand_name" do
    it "returns display_name when set" do
      church = create(:church, name: "Legal Name Inc.", display_name: "Kids Nook")
      expect(church.brand_name).to eq("Kids Nook")
    end

    it "falls back to name when display_name is blank" do
      church = create(:church, name: "Legal Name Inc.", display_name: nil)
      expect(church.brand_name).to eq("Legal Name Inc.")
    end
  end

  describe "#logo validation" do
    def attach_logo(church, content_type:, byte_size: 1.kilobyte)
      church.logo.attach(
        io: StringIO.new("x" * byte_size),
        filename: "logo.png",
        content_type: content_type
      )
    end

    it "accepts an allowed image type within the size limit" do
      church = build(:church)
      attach_logo(church, content_type: "image/png")
      expect(church).to be_valid
    end

    it "rejects a disallowed content type" do
      church = build(:church)
      attach_logo(church, content_type: "application/pdf")
      expect(church).not_to be_valid
      expect(church.errors[:logo]).to include(a_string_matching(/PNG|JPEG|SVG|WebP/))
    end

    it "rejects a logo over the size limit" do
      church = build(:church)
      attach_logo(church, content_type: "image/png", byte_size: Church::MAX_LOGO_SIZE + 1)
      expect(church).not_to be_valid
      expect(church.errors[:logo]).to include(a_string_matching(/smaller than/))
    end

    it "is valid with no logo attached at all" do
      church = build(:church)
      expect(church).to be_valid
    end
  end

  describe "#logo_shape" do
    it "defaults to circle" do
      church = create(:church)
      expect(church.logo_shape).to eq("circle")
    end

    it "accepts square and rectangle" do
      expect(build(:church, logo_shape: "square")).to be_valid
      expect(build(:church, logo_shape: "rectangle")).to be_valid
    end

    it "rejects an unknown shape" do
      church = build(:church, logo_shape: "hexagon")
      expect(church).not_to be_valid
      expect(church.errors[:logo_shape]).to be_present
    end
  end

  describe "#primary_hostname" do
    it "prefers a verified primary custom domain" do
      church = create(:church, slug: "jcc")
      create(:custom_domain, :verified, church: church, hostname: "kids.jcc.org", primary: true)
      expect(church.primary_hostname).to eq("kids.jcc.org")
    end
  end
end
