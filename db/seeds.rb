# Minimal dev seed — one family with one child, for local sanity checks.
# Run with: bundle exec rails db:seed

family = Spirely::Family.find_or_create_by!(email: "jane@example.com") do |f|
  f.family_name                  = "Doe Family"
  f.primary_contact_first_name   = "Jane"
  f.primary_contact_last_name    = "Doe"
  f.phone                        = "+15555550100"
end

family.children.find_or_create_by!(first_name: "Alex", last_name: "Doe") do |c|
  c.birthdate = 10.years.ago.to_date
  c.grade     = 4
end

puts "✅ Seeded 1 family (#{family.email}) with #{family.children.count} child(ren)"
