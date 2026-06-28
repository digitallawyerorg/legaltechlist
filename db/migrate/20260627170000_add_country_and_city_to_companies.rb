class AddCountryAndCityToCompanies < ActiveRecord::Migration[7.2]
  def change
    add_column :companies, :country, :string
    add_column :companies, :city, :string
    add_index :companies, :country
    add_index :companies, :city
  end
end
