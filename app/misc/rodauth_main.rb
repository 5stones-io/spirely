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

    # Deliberately does NOT embed church_id or role — a family's or staff
    # member's authorization comes from Current.church (resolved fresh from
    # the Host header every request) joined against Membership, not a value
    # baked into a long-lived JWT. That would let a revoked invite or a
    # church change lag until token expiry for no benefit, since the Host
    # header already gives the tenant for free on every request. The JWT is
    # purely "who" (email + exp); "where + what role" resolves per-request
    # (see Api::V1::BaseController#admin?).
    #
    # 30-day expiry (was a 2-hour default) — a short-lived token meant
    # re-requesting a magic link every time someone came back after a
    # couple hours idle. No server-side revocation exists for a JWT, so a
    # leaked token stays valid for the full window; acceptable given the
    # small number of accounts and no other higher-value target here. If
    # that trade-off stops being fine, the real fix is Rodauth's
    # jwt_refresh feature (short-lived access token + a longer-lived
    # refresh token), not just tuning this number.
    jwt_session_hash do
      base = super()
      if account
        base.merge(
          "email" => account[login_column].to_s,
          "exp"   => 30.days.from_now.to_i
        )
      else
        base
      end
    end

    # Auto-create account on first magic-link request. Downcased before
    # lookup/create — Account itself normalizes on save too, but that
    # callback runs too late to affect this find_or_create_by!'s own
    # find_by, which is why both sides need to agree independently (see
    # Account#normalize_email's comment for the case-mismatch this guards
    # against — two different-case spellings of the same email silently
    # resolving to two different Account rows).
    account_from_login do |login|
      normalized = login.to_s.strip.downcase
      Account.find_or_create_by!(email: normalized)
      @account = db[accounts_table].where(login_column => normalized).first
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
    # Always routes back to the *requesting* host (scope.request.base_url),
    # not a single static FRONTEND_BASE_URL — a church may be reached at its
    # own slug subdomain or a verified custom domain (see TenantResolution),
    # and the magic link has to land back on whichever host was actually
    # used to request it. When the request originated from the Ory Hydra
    # login bridge (bridge/login_controller.rb), a `login_challenge` param
    # is present — route the link through the bridge's callback instead of
    # the generic frontend callback so the Hydra login request gets
    # accepted once the key is verified.
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
          "#{scope.request.base_url}/auth/callback?key=#{CGI.escape(full_token)}&email=#{CGI.escape(email)}"
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
