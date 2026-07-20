class CreateSpirelyChurchIntegrations < ActiveRecord::Migration[7.2]
  def change
    create_table :spirely_church_integrations do |t|
      t.string   :token_type, null: false
      t.text     :access_token
      t.text     :refresh_token
      t.string   :scope
      t.datetime :expires_at
      t.timestamps
    end
  end
end
