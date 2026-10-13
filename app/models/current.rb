class Current < ActiveSupport::CurrentAttributes
  # custom_domain: the verified CustomDomain this request arrived on, if
  # any — narrows which modules and branding the church shows (5ST-12).
  attribute :church, :account, :membership, :custom_domain
end
