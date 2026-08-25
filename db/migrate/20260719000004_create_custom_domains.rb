class CreateCustomDomains < ActiveRecord::Migration[7.2]
  def change
    create_table :custom_domains do |t|
      t.bigint   :church_id, null: false
      t.string   :hostname, null: false
      t.datetime :verified_at
      t.string   :verification_token, null: false
      t.boolean  :primary, default: false, null: false
      t.timestamps
    end

    add_index :custom_domains, :church_id
    add_index :custom_domains, :hostname, unique: true
    add_foreign_key :custom_domains, :churches
  end
end
