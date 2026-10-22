# Kudos time served (5ST-62), fix: PCO gives each scheduled person the
# plan times they're on (PlanPerson's `times`), which is what hours served
# should come from. The first sync stored no team-to-time data at all (it
# asked for it in a way PCO answers with nothing), so every plan is marked
# for a fresh read on the next sync.
class AddTimeIdsToSpirelyServicePlanPeople < ActiveRecord::Migration[7.2]
  def up
    add_column :spirely_service_plan_people, :time_ids, :string, array: true # nil if PCO didn't say
    execute "UPDATE spirely_service_plans SET people_synced_at = NULL"
  end

  def down
    remove_column :spirely_service_plan_people, :time_ids
  end
end
