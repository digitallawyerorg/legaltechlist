class CreatePipelineRuns < ActiveRecord::Migration[7.0]
  def change
    create_table :pipeline_runs do |t|
      t.string :name, null: false
      t.string :run_type, null: false
      t.string :status, null: false, default: "pending"
      t.string :agent_name
      t.integer :records_processed, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error_message
      t.jsonb :details

      t.timestamps
    end

    add_index :pipeline_runs, :run_type
    add_index :pipeline_runs, :status
    add_index :pipeline_runs, :agent_name
    add_index :pipeline_runs, :started_at
    add_index :pipeline_runs, :finished_at
  end
end
