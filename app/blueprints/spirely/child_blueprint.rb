module Spirely
  class ChildBlueprint < ::Blueprinter::Base
    identifier :id

    fields :public_id, :first_name, :last_name, :birthdate, :notes,
           :allergens, :allergy_notes, :allergy_updated_at,
           :pco_last_synced_at, :created_at, :updated_at

    field :grade
    field :grade_display
    field :full_name
    field :age
    field :family_id
    field :allergy_summary

    # The "Linked Dual-Role Records" fix (Child#person, joined by shared
    # pco_person_id) made this possible without a schema change — nil
    # until the kid has both synced as a Child (a household sync) and
    # personally checked in at least once via PCO Check-Ins.
    #
    # checked_in_at explicitly .iso8601'd — real production bug: this is
    # a custom block field, so Blueprinter's own DateTimeFormatter (which
    # config/initializers/blueprinter.rb configures globally) never sees
    # it — that formatter only runs on a field's own top-level return
    # value, and the top-level value here is a Hash (which doesn't
    # respond_to?(:strftime)), not the Time buried inside it. Confirmed
    # live: ParentHome.tsx showed "Checked in Invalid Date at Invalid
    # Date" for a real kid's real check-in until this was added.
    field(:last_check_in) { |child|
      attendance = child.person&.attendances&.order(checked_in_at: :desc)&.first
      attendance && { event_name: attendance.event_name, checked_in_at: attendance.checked_in_at.iso8601 }
    }
  end
end
