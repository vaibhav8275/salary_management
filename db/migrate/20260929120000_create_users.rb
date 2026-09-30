class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    # The accounts that can reach the API (ARCHITECTURE §7.4). The table holds
    # only what authenticating a request needs: the login identifier and the
    # digest the submitted password is compared against. There is deliberately
    # no role column — the assessment defines a single HR persona, so there is
    # nothing to authorize against.
    #
    # Rows are never created through an endpoint. There is no registration route
    # (config/routes.rb), so this table can only grow through the
    # `auth:create_hr_user` rake task, the Rails console, or direct database
    # access — all of which are operator actions.
    create_table :users do |t|
      # Devise's `validatable` stores the login identifier here and requires it
      # to be unique; the index turns that application check into a database
      # guarantee so two concurrent sign-ins cannot both succeed.
      t.string :email, null: false, default: ""

      # The bcrypt digest written by Devise's `database_authenticatable`. The
      # `""` default matches Devise's own expectation for a password that has
      # not been set yet; no plaintext password is ever stored.
      t.string :encrypted_password, null: false, default: ""

      t.timestamps
    end

    add_index :users, :email, unique: true
  end
end
