module Bridge
  # Bridges Ory Hydra's login flow to Spirely's own Rodauth session. Hydra
  # redirects here with a `login_challenge` when a client (churchcred, a
  # future LMS, a third-party integration) starts an OAuth2 authorization
  # request. This controller does not reimplement Rodauth's credential
  # checking — it delegates to Rodauth's own real endpoints
  # (/auth/email-auth-request, /auth/email-auth) so key generation,
  # invalidation, and JWT issuance all happen exactly as they do for a
  # direct (non-Hydra) login. The login_challenge is threaded through as a
  # request param end-to-end (not the Rails session) so the flow doesn't
  # depend on session continuity between the "request link" and "click
  # link" requests.
  #
  # No design investment here yet (bare HTML) — per the "get login working
  # before any frontend" scoping for this phase.
  class LoginController < ApplicationController
    # GET /bridge/login?login_challenge=...
    def show
      challenge = params.require(:login_challenge)
      login_request = hydra.get_login_request(challenge)

      # Hydra remembers a prior accepted login (see accept_and_redirect's
      # `remember: true`) and reports skip: true on subsequent requests —
      # this is what gives SSO across churchcred/LMS/etc. without a fresh
      # login each time. Rodauth's own JWT-based session state isn't visible
      # to a plain browser redirect, so this Hydra-side remember flag is the
      # source of truth for "already logged in," not rodauth.authenticated?.
      if login_request["skip"]
        accept_and_redirect(challenge, login_request["subject"])
        return
      end

      render inline: login_form_html(challenge), layout: false
    end

    # GET /bridge/login/callback?key=...&email=...&login_challenge=...
    # Reached after the user clicks the magic-link email
    # (rodauth_main.rb#send_email_auth_email routes the link here when a
    # login_challenge was present on the original request).
    def callback
      key       = params.require(:key)
      email     = params.require(:email)
      challenge = params.require(:login_challenge)

      verify_response = HTTParty.post(
        "#{request.base_url}/auth/email-auth",
        headers: { "Content-Type" => "application/json", "Accept" => "application/json" },
        body: { key: key, email: email }.to_json
      )

      unless verify_response.success?
        render plain: "Invalid or expired sign-in link.", status: :unprocessable_entity
        return
      end

      account = Account.find_by(email: email)
      accept_and_redirect(challenge, account.id.to_s)
    end

    private

    def login_form_html(challenge)
      <<~HTML
        <!doctype html>
        <html><body>
          <h1>Sign in</h1>
          <form id="login-form">
            <label>Email <input type="email" id="email" required></label>
            <button type="submit">Send sign-in link</button>
          </form>
          <p id="msg"></p>
          <script>
            document.getElementById('login-form').addEventListener('submit', async function (e) {
              e.preventDefault();
              var email = document.getElementById('email').value;
              var res = await fetch('/auth/email-auth-request', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
                body: JSON.stringify({ login: email, login_challenge: #{challenge.to_json} })
              });
              document.getElementById('msg').textContent = res.ok
                ? 'Check your email for a sign-in link.'
                : 'Something went wrong — please try again.';
            });
          </script>
        </body></html>
      HTML
    end

    def hydra
      @hydra ||= Spirely::HydraClient.new
    end

    def accept_and_redirect(challenge, subject)
      result = hydra.accept_login_request(challenge, subject: subject, remember: true, remember_for: 2_592_000)
      redirect_to result["redirect_to"], allow_other_host: true
    end
  end
end
