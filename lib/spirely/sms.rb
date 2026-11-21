require "httparty"

module Spirely
  # Per-church Twilio credentials (Spirely::ChurchIntegration), same shape
  # as PcoClient's per-church PCO credentials — no shared platform Twilio
  # account. Used first by Front-Desk Family Quick-Add's invite delivery;
  # written generally enough (church + plain to/body) that any future
  # feature needing texting can reuse it rather than duplicating this.
  class Sms
    TWILIO_BASE_URL = "https://api.twilio.com/2010-04-01"

    # Twilio wants +15552013344. Phones on file come in any format ("(555)
    # 201-3344", "555.201.3344"), so a 10-digit US number, or 11 starting
    # with 1, gets +1; anything else is sent as it was.
    def self.e164(phone)
      digits = phone.to_s.gsub(/\D/, "")
      return "+1#{digits}" if digits.length == 10
      return "+#{digits}" if digits.length == 11 && digits.start_with?("1")
      phone
    end

    def initialize(integration)
      @integration = integration
      raise ConfigError, "Twilio isn't configured for this church" unless integration&.twilio_configured?
    end

    def send(to:, body:)
      response = HTTParty.post(
        "#{TWILIO_BASE_URL}/Accounts/#{@integration.twilio_account_sid}/Messages.json",
        basic_auth: { username: @integration.twilio_account_sid, password: @integration.twilio_auth_token },
        body: { To: self.class.e164(to), From: @integration.twilio_from_number, Body: body }
      )

      unless response.success?
        raise SmsError.new("Twilio API returned #{response.code}", status: response.code, body: response.body)
      end

      response.parsed_response
    end
  end
end
