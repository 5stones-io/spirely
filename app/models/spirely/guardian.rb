module Spirely
  class Guardian < ApplicationRecord
    RELATIONSHIPS = %w[Mother Father Stepmother Stepfather Grandparent Guardian Other].freeze

    belongs_to :family

    validates :first_name,   presence: true
    validates :relationship, inclusion: { in: RELATIONSHIPS }, allow_blank: true
  end
end
