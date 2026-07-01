class AddFoundedYearProvenanceToCompanies < ActiveRecord::Migration[8.0]
  def change
    add_column :companies, :founded_year_provenance, :jsonb
  end
end
