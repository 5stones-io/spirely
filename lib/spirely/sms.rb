require "httparty"

module Spirely
  # Per-church Twilio credentials (Spirely::ChurchIntegration), same shape
  # as PcoClient's per-church PCO credentials — no shared platform Twilio
  # account. Used first by Front-Desk Family Quick-Add's invite delivery;
  # written generally enough (church + plain to/body) that any future
  # feature needing texting can reuse it rather than duplicating this.
  class Sms
    TWILIO_BASE_URL = "https://api.twilio.com/2010-04-01"

    def initialize(integration)
      @integration = integration
      raise ConfigError, "Twilio isn't configured for this church" unless integration&.twilio_configured?
    end

    def send(to:, body:)
      response = HTTParty.post(
        "#{TWILIO_BASE_URL}/Accounts/#{@integration.twilio_account_sid}/Messages.json",
        basic_auth: { username: @integration.twilio_account_sid, password: @integration.twilio_auth_token },
        body: { To: to, From: @integration.twilio_from_number, Body: body }
      )

      unless response.success?
        raise SmsError.new("Twilio API returned #{response.code}", status: response.code, body: response.body)
      end

      response.parsed_response
    end
  end
end
