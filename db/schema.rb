# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_08_31_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  create_table "account_email_auth_keys", force: :cascade do |t|
    t.string "key", null: false
    t.datetime "deadline", null: false
    t.datetime "email_last_sent", default: -> { "CURRENT_TIMESTAMP" }, null: false
  end

  create_table "account_lockouts", force: :cascade do |t|
    t.string "key", null: false
    t.datetime "deadline", null: false
    t.datetime "email_last_sent"
  end

  create_table "account_login_failures", force: :cascade do |t|
    t.integer "number", default: 1, null: false
  end

  create_table "accounts", force: :cascade do |t|
    t.string "email", null: false
    t.string "phone"
    t.boolean "admin", default: false, null: false
    t.integer "status_id", default: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_accounts_on_email", unique: true, where: "(status_id <> 3)"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "churches", force: :cascade do |t|
    t.string "slug", null: false
    t.string "name", null: false
    t.string "enabled_modules", default: [], null: false, array: true
    t.string "status", default: "pending", null: false
    t.boolean "session_recording_enabled", default: false, null: false
    t.boolean "role_preview_enabled", default: false, null: false
    t.string "public_site_theme", default: "default", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "display_name"
    t.string "logo_shape", default: "circle", null: false
    t.boolean "family_posts_moderation_enabled", default: false, null: false
    t.index ["slug"], name: "index_churches_on_slug", unique: true
  end

  create_table "custom_domains", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.string "hostname", null: false
    t.datetime "verified_at"
    t.string "verification_token", null: false
    t.boolean "primary", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["church_id"], name: "index_custom_domains_on_church_id"
    t.index ["hostname"], name: "index_custom_domains_on_hostname", unique: true
  end

  create_table "memberships", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "church_id", null: false
    t.string "role", default: "family", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "church_id"], name: "index_memberships_on_account_id_and_church_id", unique: true
    t.index ["church_id"], name: "index_memberships_on_church_id"
  end

  create_table "spirely_attendances", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.bigint "person_id", null: false
    t.string "pco_check_in_id", null: false
    t.string "pco_event_id", null: false
    t.string "event_name", null: false
    t.string "pco_location_id"
    t.string "location_name"
    t.datetime "checked_in_at", null: false
    t.datetime "checked_out_at"
    t.string "kind", null: false
    t.boolean "one_time_guest", default: false, null: false
    t.text "medical_notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["church_id", "pco_check_in_id"], name: "index_spirely_attendances_on_church_id_and_pco_check_in_id", unique: true
    t.index ["person_id", "pco_event_id", "checked_in_at"], name: "index_attendances_on_person_event_checkin"
  end

  create_table "spirely_children", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.bigint "family_id", null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.date "birthdate"
    t.text "notes"
    t.integer "grade"
    t.string "pco_person_id"
    t.datetime "pco_last_synced_at"
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.text "allergens", default: [], null: false, array: true
    t.text "allergy_notes"
    t.datetime "allergy_updated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["church_id"], name: "index_spirely_children_on_church_id"
    t.index ["family_id"], name: "index_spirely_children_on_family_id"
    t.index ["pco_person_id"], name: "index_spirely_children_on_pco_person_id"
    t.index ["public_id"], name: "index_spirely_children_on_public_id", unique: true
  end

  create_table "spirely_church_integrations", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.string "token_type", null: false
    t.text "access_token"
    t.text "refresh_token"
    t.string "scope"
    t.datetime "expires_at"
    t.string "pco_client_id"
    t.text "pco_client_secret"
    t.string "pco_pat_app_id"
    t.text "pco_pat_secret"
    t.string "twilio_account_sid"
    t.text "twilio_auth_token"
    t.string "twilio_from_number"
    t.datetime "twilio_verified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["church_id"], name: "index_spirely_church_integrations_on_church_id", unique: true
  end

  create_table "spirely_families", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.string "family_name"
    t.string "email"
    t.string "phone"
    t.string "address"
    t.string "primary_contact_first_name"
    t.string "primary_contact_last_name"
    t.string "pco_person_id"
    t.string "pco_household_id"
    t.boolean "pco_sync_enabled", default: true, null: false
    t.datetime "pco_last_synced_at"
    t.datetime "pco_created_at"
    t.bigint "account_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["church_id", "account_id"], name: "index_spirely_families_on_church_id_and_account_id", unique: true, where: "(account_id IS NOT NULL)"
    t.index ["church_id"], name: "index_spirely_families_on_church_id"
    t.index ["email"], name: "index_spirely_families_on_email"
    t.index ["pco_household_id"], name: "index_spirely_families_on_pco_household_id"
    t.index ["pco_person_id"], name: "index_spirely_families_on_pco_person_id"
  end

  create_table "spirely_family_posts", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.bigint "family_id", null: false
    t.bigint "guardian_id"
    t.bigint "child_id"
    t.string "post_type", default: "prayer_request", null: false
    t.string "audience", default: "church", null: false
    t.string "status", null: false
    t.text "body", null: false
    t.text "rejected_reason"
    t.bigint "moderated_by_membership_id"
    t.datetime "moderated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["church_id", "audience", "status"], name: "idx_on_church_id_audience_status_b706e82226"
    t.index ["church_id", "status"], name: "index_spirely_family_posts_on_church_id_and_status"
    t.index ["church_id"], name: "index_spirely_family_posts_on_church_id"
    t.index ["family_id"], name: "index_spirely_family_posts_on_family_id"
  end

  create_table "spirely_guardians", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.bigint "family_id", null: false
    t.string "first_name", null: false
    t.string "last_name"
    t.string "phone"
    t.string "email"
    t.string "relationship"
    t.string "pco_person_id"
    t.bigint "account_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["church_id", "account_id"], name: "index_spirely_guardians_on_church_id_and_account_id", unique: true, where: "(account_id IS NOT NULL)"
    t.index ["church_id", "pco_person_id"], name: "index_spirely_guardians_on_church_id_and_pco_person_id", unique: true, where: "(pco_person_id IS NOT NULL)"
    t.index ["church_id"], name: "index_spirely_guardians_on_church_id"
    t.index ["family_id"], name: "index_spirely_guardians_on_family_id"
  end

  create_table "spirely_invitations", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.bigint "family_id", null: false
    t.bigint "guardian_id"
    t.string "token", null: false
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["church_id"], name: "index_spirely_invitations_on_church_id"
    t.index ["family_id"], name: "index_spirely_invitations_on_family_id"
    t.index ["guardian_id"], name: "index_spirely_invitations_on_guardian_id"
    t.index ["token"], name: "index_spirely_invitations_on_token", unique: true
  end

  create_table "spirely_people", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.string "pco_person_id", null: false
    t.string "first_name", null: false
    t.string "last_name"
    t.string "email"
    t.string "phone"
    t.boolean "child", default: false, null: false
    t.date "birthdate"
    t.datetime "pco_last_synced_at"
    t.string "assessment_result"
    t.datetime "assessment_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["church_id", "pco_person_id"], name: "index_spirely_people_on_church_id_and_pco_person_id", unique: true
  end

  create_table "spirely_staff_invitations", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.string "token", null: false
    t.string "invited_first_name"
    t.string "invited_email"
    t.string "invited_phone"
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["church_id"], name: "index_spirely_staff_invitations_on_church_id"
    t.index ["token"], name: "index_spirely_staff_invitations_on_token", unique: true
  end

  create_table "spirely_sync_settings", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.boolean "inbound_people_sync", default: true, null: false
    t.boolean "outbound_people_sync", default: false, null: false
    t.integer "sync_frequency_hours", default: 6, null: false
    t.string "conflict_resolution", default: "pco_wins", null: false
    t.datetime "last_synced_at"
    t.string "pco_ministry_tag"
    t.boolean "auto_sync_enabled", default: false, null: false
    t.jsonb "pco_kids_service_types", default: [], null: false
    t.jsonb "pco_event_tags", default: [], null: false
    t.string "pco_assessment_field_id"
    t.string "pco_assessment_field_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["church_id"], name: "index_spirely_sync_settings_on_church_id", unique: true
  end

  create_table "spirely_tasks", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "status", default: "not_started", null: false
    t.date "due_date"
    t.bigint "assignee_membership_id"
    t.bigint "created_by_membership_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "recurrence_rule", default: "none", null: false
    t.integer "recurrence_interval"
    t.string "recurrence_mode"
    t.uuid "recurrence_series_id"
    t.datetime "completed_at"
    t.datetime "next_occurrence_generated_at"
    t.boolean "sync_to_pco", default: false, null: false
    t.index ["assignee_membership_id"], name: "index_spirely_tasks_on_assignee_membership_id"
    t.index ["church_id", "status"], name: "index_spirely_tasks_on_church_id_and_status"
    t.index ["church_id"], name: "index_spirely_tasks_on_church_id"
    t.index ["recurrence_mode", "next_occurrence_generated_at", "due_date"], name: "index_spirely_tasks_on_absolute_recurrence_sweep"
    t.index ["recurrence_series_id"], name: "index_spirely_tasks_on_recurrence_series_id"
  end

  add_foreign_key "account_email_auth_keys", "accounts", column: "id"
  add_foreign_key "account_lockouts", "accounts", column: "id"
  add_foreign_key "account_login_failures", "accounts", column: "id"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "custom_domains", "churches"
  add_foreign_key "memberships", "accounts"
  add_foreign_key "memberships", "churches"
  add_foreign_key "spirely_attendances", "churches"
  add_foreign_key "spirely_attendances", "spirely_people", column: "person_id"
  add_foreign_key "spirely_children", "churches"
  add_foreign_key "spirely_children", "spirely_families", column: "family_id"
  add_foreign_key "spirely_church_integrations", "churches"
  add_foreign_key "spirely_families", "accounts", on_delete: :nullify
  add_foreign_key "spirely_families", "churches"
  add_foreign_key "spirely_family_posts", "churches"
  add_foreign_key "spirely_family_posts", "memberships", column: "moderated_by_membership_id", on_delete: :nullify
  add_foreign_key "spirely_family_posts", "spirely_children", column: "child_id", on_delete: :nullify
  add_foreign_key "spirely_family_posts", "spirely_families", column: "family_id"
  add_foreign_key "spirely_family_posts", "spirely_guardians", column: "guardian_id", on_delete: :nullify
  add_foreign_key "spirely_guardians", "churches"
  add_foreign_key "spirely_guardians", "spirely_families", column: "family_id"
  add_foreign_key "spirely_invitations", "churches"
  add_foreign_key "spirely_invitations", "spirely_families", column: "family_id"
  add_foreign_key "spirely_invitations", "spirely_guardians", column: "guardian_id"
  add_foreign_key "spirely_people", "churches"
  add_foreign_key "spirely_staff_invitations", "churches"
  add_foreign_key "spirely_sync_settings", "churches"
  add_foreign_key "spirely_tasks", "churches"
  add_foreign_key "spirely_tasks", "memberships", column: "assignee_membership_id", on_delete: :nullify
  add_foreign_key "spirely_tasks", "memberships", column: "created_by_membership_id", on_delete: :nullify
end
