class AddTaxonomyFacetColumns < ActiveRecord::Migration[8.0]
  def change
    add_reference :companies, :secondary_category, foreign_key: { to_table: :categories }, index: true
    add_reference :companies, :successor_company, foreign_key: { to_table: :companies }, index: true
  end
end
