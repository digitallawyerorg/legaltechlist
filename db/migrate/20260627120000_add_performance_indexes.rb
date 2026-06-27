class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    add_index :companies, :visible
    add_index :companies, [:visible, :founded_date], order: { founded_date: :desc }
    add_index :companies, [:visible, :created_at], order: { created_at: :desc }
    add_index :companies, :name, using: :gin, opclass: :gin_trgm_ops
    add_index :tags, :name
  end
end
