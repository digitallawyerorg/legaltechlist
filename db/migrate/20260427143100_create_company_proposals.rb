class CreateCompanyProposals < ActiveRecord::Migration[7.0]
  def change
    create_table :company_proposals do |t|
      t.string :status, null: false, default: "pending"
      t.string :proposal_type, null: false, default: "atlas_candidate"
      t.string :source, null: false, default: "legaltechatlas_csv"
      t.string :source_identifier
      t.jsonb :source_payload, null: false, default: {}
      t.jsonb :proposed_changes, null: false, default: {}
      t.jsonb :final_changes, null: false, default: {}
      t.jsonb :duplicate_signals, null: false, default: {}
      t.jsonb :agent_details, null: false, default: {}
      t.text :reviewer_notes
      t.text :rejection_reason
      t.references :admin_user, foreign_key: true
      t.references :company, foreign_key: true
      t.datetime :reviewed_at
      t.datetime :approved_at
      t.datetime :rejected_at
      t.datetime :enriched_at

      t.timestamps
    end

    add_index :company_proposals, :status
    add_index :company_proposals, :proposal_type
    add_index :company_proposals, :source
    add_index :company_proposals, :source_identifier
  end
end
