class CreateCompanyBusinessModels < ActiveRecord::Migration[8.0]
  def up
    create_table :company_business_models do |t|
      t.references :company, null: false, foreign_key: true
      t.references :business_model, null: false, foreign_key: true
      t.timestamps
    end

    add_index :company_business_models, [:company_id, :business_model_id], unique: true, name: "index_company_business_models_uniqueness"

    execute <<~SQL.squish
      INSERT INTO company_business_models (company_id, business_model_id, created_at, updated_at)
      SELECT id, business_model_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM companies
      WHERE business_model_id IS NOT NULL
    SQL
  end

  def down
    drop_table :company_business_models
  end
end
