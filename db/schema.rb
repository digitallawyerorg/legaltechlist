# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2026_04_26_210500) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_admin_comments", force: :cascade do |t|
    t.string "namespace"
    t.text "body"
    t.string "resource_id", null: false
    t.string "resource_type", null: false
    t.string "author_type"
    t.bigint "author_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_type", "author_id"], name: "index_active_admin_comments_on_author"
    t.index ["author_type", "author_id"], name: "index_active_admin_comments_on_author_type_and_author_id"
    t.index ["namespace"], name: "index_active_admin_comments_on_namespace"
    t.index ["resource_type", "resource_id"], name: "index_active_admin_comments_on_resource_type_and_resource_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", precision: nil, null: false
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.inet "current_sign_in_ip"
    t.inet "last_sign_in_ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
  end

  create_table "business_models", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "categories", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "companies", force: :cascade do |t|
    t.string "name"
    t.string "location"
    t.string "founded_date"
    t.text "description"
    t.string "main_url"
    t.string "twitter_url"
    t.string "angellist_url"
    t.string "crunchbase_url"
    t.string "linkedin_url"
    t.string "facebook_url"
    t.string "legalio_url"
    t.string "status"
    t.string "employee_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "category_id"
    t.bigint "target_client_id"
    t.bigint "business_model_id"
    t.bigint "sub_category_id"
    t.float "latitude"
    t.float "longitude"
    t.boolean "visible", default: true
    t.string "contact_email"
    t.string "contact_name"
    t.boolean "codex_presenter"
    t.date "codex_presentation_date"
    t.string "logo_url"
    t.decimal "total_funding_amount_usd", precision: 15, scale: 2
    t.string "funding_status"
    t.integer "number_of_funding_rounds"
    t.date "exit_date"
    t.string "founders"
    t.string "headquarters_region"
    t.string "quality_status"
    t.string "verification_verdict"
    t.integer "quality_score"
    t.jsonb "quality_review"
    t.datetime "verified_at"
    t.datetime "enriched_at"
    t.datetime "quality_reviewed_at"
    t.datetime "human_reviewed_at"
    t.string "fingerprint"
    t.string "canonical_domain"
    t.string "source"
    t.string "source_url"
    t.index ["business_model_id"], name: "index_companies_on_business_model_id"
    t.index ["canonical_domain"], name: "index_companies_on_canonical_domain"
    t.index ["category_id"], name: "index_companies_on_category_id"
    t.index ["fingerprint"], name: "index_companies_on_fingerprint"
    t.index ["human_reviewed_at"], name: "index_companies_on_human_reviewed_at"
    t.index ["quality_score"], name: "index_companies_on_quality_score"
    t.index ["quality_status"], name: "index_companies_on_quality_status"
    t.index ["sub_category_id"], name: "index_companies_on_sub_category_id"
    t.index ["target_client_id"], name: "index_companies_on_target_client_id"
    t.index ["verification_verdict"], name: "index_companies_on_verification_verdict"
    t.index ["verified_at"], name: "index_companies_on_verified_at"
  end

  create_table "sub_categories", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.bigint "category_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_sub_categories_on_category_id"
  end

  create_table "taggings", force: :cascade do |t|
    t.bigint "company_id"
    t.bigint "tag_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_taggings_on_company_id"
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
  end

  create_table "tags", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "target_clients", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "companies", "business_models"
  add_foreign_key "companies", "categories"
  add_foreign_key "companies", "sub_categories"
  add_foreign_key "companies", "target_clients"
  add_foreign_key "sub_categories", "categories"
  add_foreign_key "taggings", "companies"
  add_foreign_key "taggings", "tags"
end
