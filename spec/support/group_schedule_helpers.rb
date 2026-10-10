# Builds a small, scheduled group for the Small Groups schedule specs.
module GroupScheduleHelpers
  def schedule_group(church, name: "Moms Connect", jobs: %w[lead host_home refreshments])
    church.groups.create!(name: name, pco_group_id: "g-#{SecureRandom.hex(4)}", schedule_jobs: jobs, location_name: "Fellowship Hall")
  end

  def join(church, group, role: "member", first: Faker::Name.first_name, email: nil, phone: nil, head: false)
    person = create(:spirely_person, church: church, first_name: first, last_name: "Test", email: email || "#{first.downcase}-#{SecureRandom.hex(3)}@example.com", phone: phone)
    church.group_memberships.create!(group: group, person: person, role: role, head_leader: head,
                                     pco_membership_id: "m-#{SecureRandom.hex(4)}", joined_at: 1.year.ago)
    person
  end

  def meeting(church, group, at)
    church.group_events.create!(group: group, pco_event_id: "e-#{SecureRandom.hex(4)}", starts_at: at)
  end
end

RSpec.configure { |c| c.include GroupScheduleHelpers }
