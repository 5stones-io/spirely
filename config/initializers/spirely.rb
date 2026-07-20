Spirely.configure do |config|
  config.pco_client_id      = ENV["PCO_CLIENT_ID"]
  config.pco_client_secret  = ENV["PCO_CLIENT_SECRET"]
  config.pco_redirect_uri   = ENV["PCO_REDIRECT_URI"]
  config.encryption_key     = ENV["ENCRYPTION_KEY"]
  config.frontend_base_url  = ENV["FRONTEND_BASE_URL"]
  config.pco_ministry_tag   = ENV["PCO_MINISTRY_TAG"]
  config.twilio_account_sid = ENV["TWILIO_ACCOUNT_SID"]
  config.twilio_auth_token  = ENV["TWILIO_AUTH_TOKEN"]
  config.twilio_from_number = ENV["TWILIO_FROM_NUMBER"]
  config.hydra_admin_url    = ENV.fetch("HYDRA_ADMIN_URL", "http://localhost:4445")
end
