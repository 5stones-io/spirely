require "sequel/core"
require "cgi"

class RodauthMain < Rodauth::Rails::Auth
  configure do
    enable :email_auth, :jwt

    # Connect Sequel to ActiveRecord's connection pool (no separate DB config needed).
    db Sequel.postgres(extensions: :activerecord_connection, keep_reference: false)

    prefix "/auth"
    only_json? true
    convert_token_id_to_integer? true

    jwt_secret { Rails.application.secret_key_base }

    # Add email + admin + 2-hour expiry to the JWT payload.
    # Guard against nil account (Rodauth calls set_jwt on error responses too).
    jwt_session_hash do
      base = super()
      if account
        base.merge(
          "email" => account[login_column].to_s,
          "admin" => (account[:admin] || false),
          "exp"   => (Time.now + 7_200).to_i
        )
      else
        base
      end
    end

    # Auto-create account on first magic-link request.
    account_from_login do |login|
      Account.find_or_create_by!(email: login)
      @account = db[accounts_table].where(login_column => login).first
    end

    # Verify magic link key. Rodauth's built-in account_from_key uses string-to-bigint
    # comparison that fails with bound parameters, so we implement the lookup directly.
    account_from_email_auth_key do |token|
      id_str, key_val = token.split("_", 2)
      next nil unless id_str && key_val

      id_int = id_str.to_i
      next nil unless id_int > 0

      stored = db[email_auth_table]
                 .where(email_auth_id_column => id_int)
                 .where(Sequel::CURRENT_TIMESTAMP <= email_auth_deadline_column)
                 .get(email_auth_key_column)
      next nil unless stored && Rack::Utils.secure_compare(stored.ljust(key_val.length), key_val) && stored.length == key_val.length

      @account = db[accounts_table]
                   .where(account_id_column => id_int)
                   .where(account_status_column => account_open_status_value)
                   .first
    end

    # Build magic link with full Rodauth token format: account_id + separator + raw_key.
    #
    # When the request originated from the Ory Hydra login bridge
    # (bridge/login_controller.rb), a `login_challenge` param is present —
    # route the link through the bridge's callback instead of the generic
    # frontend callback so the Hydra login request gets accepted once the
    # key is verified. Plain (non-Hydra) logins keep the original behavior.
    send_email_auth_email do
      email      = account[login_column]
      full_token = "#{account_id}#{token_separator}#{email_auth_key_value}"
      login_challenge = param_or_nil("login_challenge")

      link =
        if login_challenge
          "#{scope.request.base_url}/bridge/login/callback" \
          "?key=#{CGI.escape(full_token)}" \
          "&email=#{CGI.escape(email)}" \
          "&login_challenge=#{CGI.escape(login_challenge)}"
        else
          base = Spirely.configuration.frontend_base_url.presence ||
                   ENV.fetch("RAILWAY_PUBLIC_DOMAIN") { raise "FRONTEND_BASE_URL is not set" }.then { |d| "https://#{d}" }
          "#{base}/auth/callback?key=#{CGI.escape(full_token)}&email=#{CGI.escape(email)}"
        end
      Rails.logger.warn("\n\n🔐 [spirely] Magic link for #{email}:\n#{link}\n\n")

      if Rails.env.production?
        from = ENV["MAILER_FROM"].presence || "noreply@spirely.app"
        @magic_link_url = link
        html = ERB.new(File.read(Rails.root.join("app/views/rodauth_mailer/email_auth.html.erb"))).result(binding)
        text = ERB.new(File.read(Rails.root.join("app/views/rodauth_mailer/email_auth.text.erb"))).result(binding)
        resp = Resend::Emails.send({
          from:    from,
          to:      [email],
          subject: "Your spirely sign-in link",
          html:    html,
          text:    text
        })
        Rails.logger.warn("[resend] magic link send result: #{resp.inspect}")
      end
    end

    # No resend cooldown in development.
    email_auth_skip_resend_email_within(Rails.env.development? ? 0 : 300)

    # Also include the JWT in the response body so the frontend can read it
    # even if the Authorization header is stripped (e.g., CORS misconfiguration).
    after_login do
      json_response["token"] = session_jwt
    end

    rails_account_model { Account }
  end
end
