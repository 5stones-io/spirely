module Spirely
  class Error          < StandardError; end
  class PcoError       < Error; end
  class PcoAuthError   < PcoError; end   # 401 — token refresh failed
  class PcoApiError    < PcoError        # non-2xx from PCO API
    attr_reader :status, :body
    def initialize(msg = nil, status: nil, body: nil)
      @status = status
      @body   = body
      super(msg || "PCO API error (#{status})")
    end
  end
  class ConfigError    < Error; end      # missing required configuration
  class SmsError       < Error           # non-2xx from Twilio's API
    attr_reader :status, :body
    def initialize(msg = nil, status: nil, body: nil)
      @status = status
      @body   = body
      super(msg || "Twilio API error (#{status})")
    end
  end
  class HydraError     < Error           # non-2xx from Hydra's admin API
    attr_reader :status, :body
    def initialize(msg = nil, status: nil, body: nil)
      @status = status
      @body   = body
      super(msg || "Hydra admin API error (#{status})")
    end
  end
end
