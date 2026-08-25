class CreateSpirelyChurchIntegrations < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_church_integrations do |t|
      t.bigint   :church_id, null: false
      t.string   :token_type, null: false
      t.text     :access_token
      t.text     :refresh_token
      t.string   :scope
      t.datetime :expires_at
      t.string   :pco_client_id
      t.text     :pco_client_secret
      t.string   :pco_pat_app_id
      t.text     :pco_pat_secret
      t.string   :twilio_account_sid
      t.text     :twilio_auth_token
      t.string   :twilio_from_number
      t.datetime :twilio_verified_at
      t.timestamps
    end

    add_index :spirely_church_integrations, :church_id, unique: true
    add_foreign_key :spirely_church_integrations, :churches
  end
end
