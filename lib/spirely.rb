require "spirely/version"
require "spirely/errors"
require "spirely/configuration"
require "spirely/encryption"
require "spirely/pco_client"
require "spirely/sms_client"
require "spirely/hydra_client"
require "spirely/engine"

module Spirely
  class << self
    def configure
      yield configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end
  end
end
