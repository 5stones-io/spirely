module Bridge
  # Bridges Ory Hydra's consent flow. First-party 5stones apps are expected
  # to be registered with Hydra as `skip_consent` clients — for those, Hydra
  # reports skip: true here and no screen is ever shown, matching the
  # already-authenticated-app experience described in SPIRELY_CONTEXT.md.
  # This screen only renders for clients that haven't been marked trusted
  # (third-party integrations), where showing exactly what's being requested
  # matters.
  class ConsentController < ApplicationController
    # GET /bridge/consent?consent_challenge=...
    def show
      challenge = params.require(:consent_challenge)
      consent_request = hydra.get_consent_request(challenge)

      if consent_request["skip"]
        accept_and_redirect(challenge, consent_request["requested_scope"])
        return
      end

      render inline: consent_form_html(challenge, Array(consent_request["requested_scope"]),
                                        consent_request.dig("client", "client_name") || consent_request.dig("client", "client_id")),
             layout: false
    end

    # POST /bridge/consent
    def create
      challenge = params.require(:consent_challenge)
      accept_and_redirect(challenge, Array(params[:grant_scope]))
    end

    private

    def hydra
      @hydra ||= Spirely::HydraClient.new
    end

    def accept_and_redirect(challenge, scopes)
      result = hydra.accept_consent_request(challenge, grant_scope: scopes)
      redirect_to result["redirect_to"], allow_other_host: true
    end

    def consent_form_html(challenge, scopes, client_name)
      checkboxes = scopes.map { |s|
        %(<label><input type="checkbox" name="grant_scope[]" value="#{s}" checked> #{s}</label><br>)
      }.join

      <<~HTML
        <!doctype html>
        <html><body>
          <h1>#{client_name} would like to access your Spirely account</h1>
          <form method="post" action="/bridge/consent">
            <input type="hidden" name="authenticity_token" value="#{form_authenticity_token}">
            <input type="hidden" name="consent_challenge" value="#{challenge}">
            #{checkboxes}
            <button type="submit">Allow access</button>
          </form>
        </body></html>
      HTML
    end
  end
end
