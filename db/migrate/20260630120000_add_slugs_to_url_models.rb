# frozen_string_literal: true

class AddSlugsToUrlModels < ActiveRecord::Migration[8.0]
  TABLES = %i[companies categories business_models target_clients tags].freeze

  def change
    TABLES.each do |table|
      add_column table, :slug, :string
      add_index table, :slug, unique: true
    end
  end
end
