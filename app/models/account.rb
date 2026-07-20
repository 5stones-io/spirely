class Account < ApplicationRecord
  has_one :family, class_name: "Spirely::Family", foreign_key: :account_id, dependent: :nullify

  def admin? = self[:admin]
end
