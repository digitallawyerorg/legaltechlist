class AddLegaltechAtlasUrlToCompanies < ActiveRecord::Migration[7.2]
  def change
    add_column :companies, :legaltech_atlas_url, :string
    add_index :companies, :legaltech_atlas_url, where: "legaltech_atlas_url IS NOT NULL"
  end
end
