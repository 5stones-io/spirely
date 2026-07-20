module AuthHelpers
  def jwt_for(account, admin: nil)
    payload = {
      "account_id" => account.id,
      "email"      => account.email,
      "admin"      => admin.nil? ? account.admin : admin,
      "exp"        => (Time.now + 7_200).to_i
    }
    JWT.encode(payload, Rails.application.secret_key_base, "HS256")
  end

  def auth_headers(account, **opts)
    { "Authorization" => "Bearer #{jwt_for(account, **opts)}" }
  end
end
