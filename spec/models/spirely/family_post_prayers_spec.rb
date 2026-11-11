require "rails_helper"

# Prayer requests and praise reports (5ST-79): people say they're praying
# for a request, and a family marks its own request answered, optionally
# sharing what happened as a praise report.
RSpec.describe Spirely::FamilyPost, "prayer", type: :model do
  let(:church)  { create(:church) }
  let(:family)  { create(:spirely_family, church: church) }
  let(:request) { create(:spirely_family_post, church: church, family: family, post_type: "prayer_request", status: "approved") }

  describe "#pray!" do
    it "counts each account once, however often it's called" do
      account = create(:account)
      2.times { request.pray!(account) }
      request.pray!(create(:account))

      expect(request.reload.prayers_count).to eq(2)
      expect(request.praying?(account)).to be(true)
    end

    it "only works on prayer requests" do
      praise = create(:spirely_family_post, church: church, family: family, post_type: "praise_report")
      expect { praise.pray!(create(:account)) }.to raise_error(Spirely::FamilyPost::PrayerError)
    end
  end

  describe "#stop_praying!" do
    it "takes the account's prayer back off" do
      account = create(:account)
      request.pray!(account)
      request.stop_praying!(account)
      request.stop_praying!(account)

      expect(request.reload.prayers_count).to eq(0)
      expect(request.praying?(account)).to be(false)
    end
  end

  describe "#mark_answered!" do
    it "records when and what happened" do
      freeze_time do
        request.mark_answered!(note: "He's better!")
        expect(request.reload.answered_at).to eq(Time.current)
        expect(request.answer_note).to eq("He's better!")
        expect(request.answer_praise).to be_nil
      end
    end

    it "shares a praise report that points back at the request, with the same audience and child" do
      child = create(:spirely_child, family: family)
      request.update!(audience: "staff_only", child: child)

      praise = request.mark_answered!(note: "His fever broke Saturday.", share_as_praise: true)

      expect(praise).to be_persisted
      expect(praise).to have_attributes(post_type: "praise_report", body: "His fever broke Saturday.",
                                        audience: "staff_only", child_id: child.id, family_id: family.id,
                                        answers_post_id: request.id)
      expect(request.reload.answer_praise).to eq(praise)
    end

    it "needs something to say before it can share a praise report" do
      expect { request.mark_answered!(note: " ", share_as_praise: true) }
        .to raise_error(ActiveRecord::RecordInvalid)
      expect(request.reload.answered_at).to be_nil
    end

    it "can't answer a request twice, or answer something that isn't a request" do
      request.mark_answered!(note: nil)
      expect { request.mark_answered!(note: nil) }.to raise_error(Spirely::FamilyPost::PrayerError)

      praise = create(:spirely_family_post, church: church, family: family, post_type: "praise_report")
      expect { praise.mark_answered!(note: nil) }.to raise_error(Spirely::FamilyPost::PrayerError)
    end
  end

  it "only lets a praise report answer one of its own family's prayer requests" do
    other = create(:spirely_family_post, church: church, post_type: "prayer_request")
    praise = build(:spirely_family_post, church: church, family: family, post_type: "praise_report", answers_post_id: other.id)
    expect(praise).not_to be_valid
    expect(praise.errors[:answers_post]).to be_present
  end

  it "removes its prayers with it" do
    request.pray!(create(:account))
    expect { request.destroy! }.to change(Spirely::FamilyPostPrayer, :count).by(-1)
  end
end
