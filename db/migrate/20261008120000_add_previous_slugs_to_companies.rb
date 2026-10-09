class AddPreviousSlugsToCompanies < ActiveRecord::Migration[8.0]
  def change
    # Profile URLs are cited (the profile page hands out Bluebook/APA/BibTeX), so a
    # rename or a merge must not turn an old slug into a 404. Superseded slugs are kept
    # here and redirect to the record's current slug.
    add_column :companies, :previous_slugs, :string, array: true, default: [], null: false
    add_index :companies, :previous_slugs, using: :gin
  end
end
