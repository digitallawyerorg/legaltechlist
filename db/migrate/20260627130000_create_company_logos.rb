class CreateCompanyLogos < ActiveRecord::Migration[8.0]
  def change
    create_table :company_logos do |t|
      t.references :company, null: false, foreign_key: true, index: { unique: true }
      t.binary :data, null: false
      t.string :content_type, null: false, default: "image/png"

      t.timestamps
    end
  end
end
