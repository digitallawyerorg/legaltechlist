class CreateCompanyTargetClients < ActiveRecord::Migration[8.0]
  def change
    create_table :company_target_clients do |t|
      t.references :company, null: false, foreign_key: true
      t.references :target_client, null: false, foreign_key: true
      t.timestamps
    end

    add_index :company_target_clients, [:company_id, :target_client_id], unique: true, name: "index_company_target_clients_uniqueness"
  end
end
