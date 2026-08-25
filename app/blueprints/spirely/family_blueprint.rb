module Spirely
  class FamilyBlueprint < ::Blueprinter::Base
    identifier :id

    fields :family_name, :email, :phone, :address,
           :primary_contact_first_name, :primary_contact_last_name,
           :pco_sync_enabled, :pco_last_synced_at, :created_at, :updated_at

    field(:primary_contact_name) { |f| f.primary_contact_name }

    view :with_children do
      association :children, blueprint: ChildBlueprint
    end
  end
end
