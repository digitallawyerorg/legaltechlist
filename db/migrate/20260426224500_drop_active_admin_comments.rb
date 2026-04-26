class DropActiveAdminComments < ActiveRecord::Migration[7.0]
  def change
    drop_table :active_admin_comments do |t|
      t.string :namespace
      t.text :body
      t.string :resource_type
      t.bigint :resource_id
      t.string :author_type
      t.bigint :author_id
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index %i[author_type author_id], name: "index_active_admin_comments_on_author"
      t.index %i[author_type author_id], name: "index_active_admin_comments_on_author_type_and_author_id"
      t.index :namespace, name: "index_active_admin_comments_on_namespace"
      t.index %i[resource_type resource_id], name: "index_active_admin_comments_on_resource_type_and_resource_id"
    end
  end
end
