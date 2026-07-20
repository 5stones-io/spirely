namespace :spirely do
  desc "Post-deploy setup: promote ADMIN_EMAIL to admin (sign in first, then run this)"
  task first_deploy: :environment do
    email = ENV["ADMIN_EMAIL"]&.strip
    abort "Set ADMIN_EMAIL env var. Usage: ADMIN_EMAIL=you@example.com rails spirely:first_deploy" if email.blank?

    puts "\n=== spirely first-deploy setup ===\n\n"

    account = Account.find_by(email: email)
    if account
      account.update!(admin: true)
      puts "✅ #{email} promoted to admin"
    else
      puts "⚠️  No account found for #{email}"
      puts "   Sign in via magic link first, then re-run this task."
    end

    puts "\nDatabase stats:"
    puts "  Accounts:    #{Account.count}"
    puts "  Families:    #{Spirely::Family.count}"
    puts "\nRun `rails spirely:setup_check` to verify env vars.\n\n"
  end

  desc "Promote a user to admin by email. Usage: rails spirely:make_admin[email@example.com]"
  task :make_admin, [:email] => :environment do |_, args|
    email = args[:email]&.strip
    abort "Usage: bundle exec rails spirely:make_admin[email@example.com]" if email.blank?

    account = Account.find_by(email: email)
    abort "No account found with email: #{email}\n  Hint: the user must sign in at least once before being promoted." unless account

    account.update!(admin: true)
    puts "✅ #{email} is now an admin."
    puts "   They may need to sign out and back in for the change to take effect."
  end

  desc "List all admin users"
  task list_admins: :environment do
    admins = Account.where(admin: true).pluck(:email)
    if admins.empty?
      puts "No admin users found."
    else
      puts "Admin users:"
      admins.each { |e| puts "  - #{e}" }
    end
  end

  desc "Print setup checklist for a new deployment"
  task :setup_check do
    puts "\n=== spirely deployment checklist ===\n\n"

    required = {
      "DATABASE_URL"      => ENV["DATABASE_URL"],
      "REDIS_URL"         => ENV["REDIS_URL"],
      "SECRET_KEY_BASE"   => ENV["SECRET_KEY_BASE"],
      "ENCRYPTION_KEY"    => ENV["ENCRYPTION_KEY"],
      "HYDRA_SECRETS_SYSTEM" => ENV["HYDRA_SECRETS_SYSTEM"],
      "MAILER_FROM"       => ENV["MAILER_FROM"],
    }

    optional = {
      "CUSTOM_DOMAIN"      => ENV["CUSTOM_DOMAIN"],
      "PCO_CLIENT_ID"      => ENV["PCO_CLIENT_ID"],
      "TWILIO_ACCOUNT_SID" => ENV["TWILIO_ACCOUNT_SID"],
    }

    required.each do |key, val|
      status = val.present? ? "✅" : "❌ MISSING"
      puts "  #{status}  #{key}"
    end

    puts "\nOptional:"
    optional.each do |key, val|
      status = val.present? ? "✅" : "⚠️  not set"
      puts "  #{status}  #{key}"
    end

    puts "\nFirst-deploy checklist:"
    puts "  1. Set all ❌ vars in Railway → Variables"
    puts "  2. Deploy — migrations run automatically"
    puts "  3. Bring up Hydra and run `hydra migrate sql`"
    puts "  4. Register a first-party OAuth2 client with Hydra (skip_consent enabled)"
    puts "  5. Sign in and promote yourself: ADMIN_EMAIL=you@example.com rails spirely:first_deploy\n\n"
  end
end
