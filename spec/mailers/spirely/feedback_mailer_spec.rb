require "rails_helper"

RSpec.describe Spirely::FeedbackMailer do
  let(:church)  { create(:church, name: "Grace Church") }
  let(:account) { create(:account, first_name: "Megan", last_name: "Torres") }
  let(:feedback) do
    create(:spirely_feedback, church: church, account: account, sender_role: "parent", category: "reflection",
                              tone: "went_well", about: "Trunk or Treat · Sat, Oct 25", body: "The candy table ran out by 7:15.")
  end

  it "tells an admin what came in, with a link to it in the inbox" do
    mail = described_class.submitted(feedback, "admin@grace.example")

    expect(mail.to).to eq(["admin@grace.example"])
    expect(mail.subject).to eq("New feedback from Megan Torres: Event reflection")
    html = mail.html_part.body.to_s
    expect(html).to include("The candy table ran out by 7:15.")
    expect(html).to include("Trunk or Treat · Sat, Oct 25")
    expect(html).to include("https://#{church.primary_hostname}/feedback-inbox?id=#{feedback.id}")
    expect(mail.text_part.body.to_s).to include("Went well")
  end
end
