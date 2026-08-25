Spirely.configure do |config|
  config.pco_redirect_uri = ENV["PCO_REDIRECT_URI"]
  config.encryption_key   = ENV["ENCRYPTION_KEY"]
  config.hydra_admin_url  = ENV.fetch("HYDRA_ADMIN_URL", "http://localhost:4445")
end
