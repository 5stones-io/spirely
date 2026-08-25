module Spirely
  class ApplicationJob < ActiveJob::Base
    queue_as :default

    retry_on  Spirely::PcoError,   wait: :polynomially_longer, attempts: 3
    discard_on Spirely::ConfigError
  end
end
