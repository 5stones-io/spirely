require "rails_helper"

RSpec.describe CustomDomain, type: :model do
  it "generates a verification token on create" do
    domain = create(:custom_domain)
    expect(domain.verification_token).to be_present
  end

  it "is not verified until verify! is called" do
    domain = create(:custom_domain)
    expect(domain.verified?).to be(false)
    domain.verify!
    expect(domain.reload.verified?).to be(true)
  end

  it "requires a unique hostname across all churches" do
    create(:custom_domain, hostname: "kids.example.org")
    expect(build(:custom_domain, hostname: "kids.example.org")).not_to be_valid
  end
end
