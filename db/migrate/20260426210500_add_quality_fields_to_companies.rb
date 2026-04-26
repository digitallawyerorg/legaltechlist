class AddQualityFieldsToCompanies < ActiveRecord::Migration[7.0]
  def change
    add_column :companies, :quality_status, :string
    add_column :companies, :verification_verdict, :string
    add_column :companies, :quality_score, :integer
    add_column :companies, :quality_review, :jsonb
    add_column :companies, :verified_at, :datetime
    add_column :companies, :enriched_at, :datetime
    add_column :companies, :quality_reviewed_at, :datetime
    add_column :companies, :human_reviewed_at, :datetime
    add_column :companies, :fingerprint, :string
    add_column :companies, :canonical_domain, :string
    add_column :companies, :source, :string
    add_column :companies, :source_url, :string

    add_index :companies, :quality_status
    add_index :companies, :verification_verdict
    add_index :companies, :quality_score
    add_index :companies, :verified_at
    add_index :companies, :human_reviewed_at
    add_index :companies, :fingerprint
    add_index :companies, :canonical_domain
  end
end
