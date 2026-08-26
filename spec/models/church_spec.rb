require "rails_helper"

RSpec.describe Church do
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
end
