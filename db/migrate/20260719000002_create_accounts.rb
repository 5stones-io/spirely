class CreateAccounts < ActiveRecord::Migration[7.2]
  def change
    create_table :accounts do |t|
      t.string  :email,     null: false
      t.string  :phone
      t.boolean :admin,     null: false, default: false
      t.integer :status_id, null: false, default: 2  # 1=unverified 2=verified 3=closed
      t.timestamps
    end
    add_index :accounts, :email, unique: true, where: "status_id != 3"

    # email_auth: one-time magic-link keys
    create_table :account_email_auth_keys, id: false do |t|
      t.bigint   :id,              null: false, primary_key: true
      t.string   :key,             null: false
      t.datetime :deadline,        null: false
      t.datetime :email_last_sent, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    add_foreign_key :account_email_auth_keys, :accounts, column: :id

    # lockout: track consecutive failures
    create_table :account_login_failures, id: false do |t|
      t.bigint  :id,     null: false, primary_key: true
      t.integer :number, null: false, default: 1
    end
    add_foreign_key :account_login_failures, :accounts, column: :id

    create_table :account_lockouts, id: false do |t|
      t.bigint   :id,              null: false, primary_key: true
      t.string   :key,             null: false
      t.datetime :deadline,        null: false
      t.datetime :email_last_sent
    end
    add_foreign_key :account_lockouts, :accounts, column: :id
  end
end
