require "rails_helper"

RSpec.describe Spirely::Attendance, type: :model do
  it "inherits church_id from its person" do
    church = create(:church)
    person = create(:spirely_person, church: church)
    attendance = create(:spirely_attendance, person: person)

    expect(attendance.church_id).to eq(church.id)
  end

  it "requires pco_check_in_id unique per church, not globally" do
    church_a = create(:church, slug: "church-a")
    church_b = create(:church, slug: "church-b")
    create(:spirely_attendance, person: create(:spirely_person, church: church_a), pco_check_in_id: "shared-id")

    dup_same_church = build(:spirely_attendance, person: create(:spirely_person, church: church_a), pco_check_in_id: "shared-id")
    dup_other_church = build(:spirely_attendance, person: create(:spirely_person, church: church_b), pco_check_in_id: "shared-id")

    expect(dup_same_church).not_to be_valid
    expect(dup_other_church).to be_valid
  end

  it "rejects an unknown kind" do
    expect(build(:spirely_attendance, kind: "vip")).not_to be_valid
  end

  describe ".countable_for_baseline" do
    it "excludes guest kind and one_time_guest check-ins" do
      church = create(:church)
      person = create(:spirely_person, church: church)
      regular = create(:spirely_attendance, person: person, kind: "regular", one_time_guest: false)
      create(:spirely_attendance, person: person, kind: "guest", one_time_guest: false)
      create(:spirely_attendance, person: person, kind: "regular", one_time_guest: true)

      expect(Spirely::Attendance.countable_for_baseline).to contain_exactly(regular)
    end
  end
end
