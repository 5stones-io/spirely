module Spirely
  class ChildBlueprint < ::Blueprinter::Base
    identifier :id

    fields :public_id, :first_name, :last_name, :birthdate, :notes,
           :pco_last_synced_at, :created_at, :updated_at

    field :grade           # integer (PCO-compatible: 0=K, 1–12)
    field :grade_display   # human string ("K", "1st", …) for UI
    field :full_name
    field :age
    field :family_id
  end
end
