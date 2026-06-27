class CreateCompanyImportRows < ActiveRecord::Migration[8.0]
  def change
    create_table :company_import_rows do |t|
      t.references :company_import_run, null: false, foreign_key: true
      t.references :company_proposal, foreign_key: true
      t.references :company, foreign_key: true
      t.integer :row_number, null: false
      t.string :source_identifier
      t.string :canonical_domain
      t.string :status, null: false, default: "pending"
      t.string :action
      t.integer :attempts, null: false, default: 0
      t.datetime :locked_at
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error_message
      t.string :error_class
      t.jsonb :source_payload, null: false, default: {}
      t.jsonb :candidate_payload, null: false, default: {}
      t.jsonb :result_payload, null: false, default: {}
      t.jsonb :quality_report, null: false, default: {}

      t.timestamps
    end

    add_index :company_import_rows, [:company_import_run_id, :row_number], unique: true, name: "index_company_import_rows_on_run_and_row"
    add_index :company_import_rows, [:company_import_run_id, :status]
    add_index :company_import_rows, :source_identifier
    add_index :company_import_rows, :canonical_domain
  end
end
