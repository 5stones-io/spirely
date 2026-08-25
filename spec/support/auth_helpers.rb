module AuthHelpers
  def jwt_for(account)
    payload = {
      "account_id" => account.id,
      "email"      => account.email,
      "exp"        => (Time.now + 7_200).to_i
    }
    JWT.encode(payload, Rails.application.secret_key_base, "HS256")
  end

  def auth_headers(account)
    { "Authorization" => "Bearer #{jwt_for(account)}" }
  end

  # Request specs run against the default test host (www.example.com), which
  # never resolves to a tenant. Call this before making a request to simulate
  # it arriving on a specific church's subdomain instead — `host!` is the
  # documented Rails integration-test mechanism for this, persists for
  # subsequent requests in the same example.
  def use_tenant_host!(church)
    host! "#{church.slug}.example.test"
  end
end
