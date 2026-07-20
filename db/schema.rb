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

ActiveRecord::Schema[7.2].define(version: 2026_07_19_000008) do
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

  create_table "spirely_children", force: :cascade do |t|
    t.bigint "family_id", null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.date "birthdate"
    t.text "notes"
    t.integer "grade"
    t.string "pco_person_id"
    t.datetime "pco_last_synced_at"
    t.uuid "public_id", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["family_id"], name: "index_spirely_children_on_family_id"
    t.index ["pco_person_id"], name: "index_spirely_children_on_pco_person_id"
    t.index ["public_id"], name: "index_spirely_children_on_public_id", unique: true
  end

  create_table "spirely_church_integrations", force: :cascade do |t|
    t.string "token_type", null: false
    t.text "access_token"
    t.text "refresh_token"
    t.string "scope"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "spirely_families", force: :cascade do |t|
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
    t.bigint "account_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_spirely_families_on_account_id", unique: true, where: "(account_id IS NOT NULL)"
    t.index ["email"], name: "index_spirely_families_on_email"
    t.index ["pco_household_id"], name: "index_spirely_families_on_pco_household_id"
    t.index ["pco_person_id"], name: "index_spirely_families_on_pco_person_id"
  end

  create_table "spirely_guardians", force: :cascade do |t|
    t.bigint "family_id", null: false
    t.string "first_name", null: false
    t.string "last_name"
    t.string "phone"
    t.string "email"
    t.string "relationship"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["family_id"], name: "index_spirely_guardians_on_family_id"
  end

  create_table "spirely_invitations", force: :cascade do |t|
    t.bigint "family_id", null: false
    t.string "token", null: false
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["family_id"], name: "index_spirely_invitations_on_family_id"
    t.index ["token"], name: "index_spirely_invitations_on_token", unique: true
  end

  create_table "spirely_sync_settings", force: :cascade do |t|
    t.boolean "inbound_people_sync", default: true, null: false
    t.boolean "outbound_people_sync", default: false, null: false
    t.integer "sync_frequency_hours", default: 6, null: false
    t.string "conflict_resolution", default: "pco_wins", null: false
    t.datetime "last_synced_at"
    t.string "pco_ministry_tag"
    t.boolean "auto_sync_enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "account_email_auth_keys", "accounts", column: "id"
  add_foreign_key "account_lockouts", "accounts", column: "id"
  add_foreign_key "account_login_failures", "accounts", column: "id"
  add_foreign_key "spirely_children", "spirely_families", column: "family_id"
  add_foreign_key "spirely_families", "accounts", on_delete: :nullify
  add_foreign_key "spirely_guardians", "spirely_families", column: "family_id"
  add_foreign_key "spirely_invitations", "spirely_families", column: "family_id"
end
