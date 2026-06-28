class AddUserSubmissionFieldsToCompanyProposals < ActiveRecord::Migration[8.0]
  def change
    change_table :company_proposals, bulk: true do |t|
      t.string :submitter_email
      t.string :submitter_name
      t.string :issue_type
      t.string :slack_message_ts
      t.text :user_message
    end

    add_index :company_proposals, :submitter_email
  end
end
