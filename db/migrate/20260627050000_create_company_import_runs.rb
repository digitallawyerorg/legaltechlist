class CreateCompanyImportRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :company_import_runs do |t|
      t.string :source, null: false, default: "legaltechatlas_csv"
      t.string :filename, null: false
      t.string :status, null: false, default: "pending"
      t.text :notes
      t.string :reviewer
      t.integer :total_rows, null: false, default: 0
      t.integer :processed_rows, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error_message
      t.jsonb :summary, null: false, default: {}

      t.timestamps
    end

    add_index :company_import_runs, :status
    add_index :company_import_runs, :source
  end
end
