require "rails_helper"

RSpec.describe Spirely::TaggedPostMailer do
  let(:church) { create(:church, name: "Grace Church", enabled_modules: ["kidsmin"]) }
  let(:staff)  { create(:membership, :admin, church: church, account: create(:account, first_name: "Maria", last_name: "Rivera")) }
  let(:family) { create(:spirely_family, church: church) }
  let(:emma)   { create(:spirely_child, family: family, first_name: "Emma") }
  let(:noah)   { create(:spirely_child, family: family, first_name: "Noah") }

  it "tells a family which of their children were tagged, linking to the feed" do
    post = Spirely::FamilyPost.post_to_families!(church: church, author: staff, body: "Psalm 23 crafts today!", child_ids: [emma.id, noah.id])

    mail = described_class.tagged(post, family, "parent@example.com")

    expect(mail.to).to eq(["parent@example.com"])
    expect(mail.subject).to eq("Maria Rivera posted about Emma and Noah")
    html = mail.html_part.body.to_s
    expect(html).to include("Psalm 23 crafts today!")
    expect(html).to include("https://#{church.primary_hostname}/family-feed")
    expect(mail.text_part.body.to_s).to include("Grace Church")
  end
end
