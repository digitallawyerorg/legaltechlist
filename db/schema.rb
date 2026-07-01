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

ActiveRecord::Schema[8.0].define(version: 2026_06_30_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

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
    t.string "slug"
    t.index ["slug"], name: "index_business_models_on_slug", unique: true
  end

  create_table "categories", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "slug"
    t.index ["slug"], name: "index_categories_on_slug", unique: true
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
    t.bigint "secondary_category_id"
    t.bigint "successor_company_id"
    t.string "country"
    t.string "city"
    t.string "legaltech_atlas_url"
    t.string "slug"
    t.index ["business_model_id"], name: "index_companies_on_business_model_id"
    t.index ["canonical_domain"], name: "index_companies_on_canonical_domain"
    t.index ["category_id"], name: "index_companies_on_category_id"
    t.index ["city"], name: "index_companies_on_city"
    t.index ["country"], name: "index_companies_on_country"
    t.index ["fingerprint"], name: "index_companies_on_fingerprint"
    t.index ["human_reviewed_at"], name: "index_companies_on_human_reviewed_at"
    t.index ["legaltech_atlas_url"], name: "index_companies_on_legaltech_atlas_url", where: "(legaltech_atlas_url IS NOT NULL)"
    t.index ["name"], name: "index_companies_on_name", opclass: :gin_trgm_ops, using: :gin
    t.index ["quality_score"], name: "index_companies_on_quality_score"
    t.index ["quality_status"], name: "index_companies_on_quality_status"
    t.index ["secondary_category_id"], name: "index_companies_on_secondary_category_id"
    t.index ["slug"], name: "index_companies_on_slug", unique: true
    t.index ["sub_category_id"], name: "index_companies_on_sub_category_id"
    t.index ["successor_company_id"], name: "index_companies_on_successor_company_id"
    t.index ["target_client_id"], name: "index_companies_on_target_client_id"
    t.index ["verification_verdict"], name: "index_companies_on_verification_verdict"
    t.index ["verified_at"], name: "index_companies_on_verified_at"
    t.index ["visible", "created_at"], name: "index_companies_on_visible_and_created_at", order: { created_at: :desc }
    t.index ["visible", "founded_date"], name: "index_companies_on_visible_and_founded_date", order: { founded_date: :desc }
    t.index ["visible"], name: "index_companies_on_visible"
  end

  create_table "company_business_models", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "business_model_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_model_id"], name: "index_company_business_models_on_business_model_id"
    t.index ["company_id", "business_model_id"], name: "index_company_business_models_uniqueness", unique: true
    t.index ["company_id"], name: "index_company_business_models_on_company_id"
  end

  create_table "company_import_rows", force: :cascade do |t|
    t.bigint "company_import_run_id", null: false
    t.bigint "company_proposal_id"
    t.bigint "company_id"
    t.integer "row_number", null: false
    t.string "source_identifier"
    t.string "canonical_domain"
    t.string "status", default: "pending", null: false
    t.string "action"
    t.integer "attempts", default: 0, null: false
    t.datetime "locked_at"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.text "error_message"
    t.string "error_class"
    t.jsonb "source_payload", default: {}, null: false
    t.jsonb "candidate_payload", default: {}, null: false
    t.jsonb "result_payload", default: {}, null: false
    t.jsonb "quality_report", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["canonical_domain"], name: "index_company_import_rows_on_canonical_domain"
    t.index ["company_id"], name: "index_company_import_rows_on_company_id"
    t.index ["company_import_run_id", "row_number"], name: "index_company_import_rows_on_run_and_row", unique: true
    t.index ["company_import_run_id", "status"], name: "index_company_import_rows_on_company_import_run_id_and_status"
    t.index ["company_import_run_id"], name: "index_company_import_rows_on_company_import_run_id"
    t.index ["company_proposal_id"], name: "index_company_import_rows_on_company_proposal_id"
    t.index ["source_identifier"], name: "index_company_import_rows_on_source_identifier"
  end

  create_table "company_import_runs", force: :cascade do |t|
    t.string "source", default: "legaltechatlas_csv", null: false
    t.string "filename", null: false
    t.string "status", default: "pending", null: false
    t.text "notes"
    t.string "reviewer"
    t.integer "total_rows", default: 0, null: false
    t.integer "processed_rows", default: 0, null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.text "error_message"
    t.jsonb "summary", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source"], name: "index_company_import_runs_on_source"
    t.index ["status"], name: "index_company_import_runs_on_status"
  end

  create_table "company_logos", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.binary "data", null: false
    t.string "content_type", default: "image/png", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_company_logos_on_company_id", unique: true
  end

  create_table "company_proposals", force: :cascade do |t|
    t.string "status", default: "pending", null: false
    t.string "proposal_type", default: "atlas_candidate", null: false
    t.string "source", default: "legaltechatlas_csv", null: false
    t.string "source_identifier"
    t.jsonb "source_payload", default: {}, null: false
    t.jsonb "proposed_changes", default: {}, null: false
    t.jsonb "final_changes", default: {}, null: false
    t.jsonb "duplicate_signals", default: {}, null: false
    t.jsonb "agent_details", default: {}, null: false
    t.text "reviewer_notes"
    t.text "rejection_reason"
    t.bigint "admin_user_id"
    t.bigint "company_id"
    t.datetime "reviewed_at"
    t.datetime "approved_at"
    t.datetime "rejected_at"
    t.datetime "enriched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "submitter_email"
    t.string "submitter_name"
    t.string "issue_type"
    t.string "slack_message_ts"
    t.text "user_message"
    t.index ["admin_user_id"], name: "index_company_proposals_on_admin_user_id"
    t.index ["company_id"], name: "index_company_proposals_on_company_id"
    t.index ["proposal_type"], name: "index_company_proposals_on_proposal_type"
    t.index ["source"], name: "index_company_proposals_on_source"
    t.index ["source_identifier"], name: "index_company_proposals_on_source_identifier"
    t.index ["status"], name: "index_company_proposals_on_status"
    t.index ["submitter_email"], name: "index_company_proposals_on_submitter_email"
  end

  create_table "company_target_clients", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "target_client_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "target_client_id"], name: "index_company_target_clients_uniqueness", unique: true
    t.index ["company_id"], name: "index_company_target_clients_on_company_id"
    t.index ["target_client_id"], name: "index_company_target_clients_on_target_client_id"
  end

  create_table "models", force: :cascade do |t|
    t.string "model_id", null: false
    t.string "name", null: false
    t.string "provider", null: false
    t.string "family"
    t.datetime "model_created_at"
    t.integer "context_window"
    t.integer "max_output_tokens"
    t.date "knowledge_cutoff"
    t.jsonb "modalities", default: {}
    t.jsonb "capabilities", default: []
    t.jsonb "pricing", default: {}
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["capabilities"], name: "index_models_on_capabilities", using: :gin
    t.index ["family"], name: "index_models_on_family"
    t.index ["modalities"], name: "index_models_on_modalities", using: :gin
    t.index ["provider", "model_id"], name: "index_models_on_provider_and_model_id", unique: true
    t.index ["provider"], name: "index_models_on_provider"
  end

  create_table "pipeline_runs", force: :cascade do |t|
    t.string "name", null: false
    t.string "run_type", null: false
    t.string "status", default: "pending", null: false
    t.string "agent_name"
    t.integer "records_processed", default: 0, null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.text "error_message"
    t.jsonb "details"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_name"], name: "index_pipeline_runs_on_agent_name"
    t.index ["finished_at"], name: "index_pipeline_runs_on_finished_at"
    t.index ["run_type"], name: "index_pipeline_runs_on_run_type"
    t.index ["started_at"], name: "index_pipeline_runs_on_started_at"
    t.index ["status"], name: "index_pipeline_runs_on_status"
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
    t.string "slug"
    t.index ["name"], name: "index_tags_on_name"
    t.index ["slug"], name: "index_tags_on_slug", unique: true
  end

  create_table "target_clients", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "slug"
    t.index ["slug"], name: "index_target_clients_on_slug", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "companies", "business_models"
  add_foreign_key "companies", "categories"
  add_foreign_key "companies", "categories", column: "secondary_category_id"
  add_foreign_key "companies", "companies", column: "successor_company_id"
  add_foreign_key "companies", "sub_categories"
  add_foreign_key "companies", "target_clients"
  add_foreign_key "company_business_models", "business_models"
  add_foreign_key "company_business_models", "companies"
  add_foreign_key "company_import_rows", "companies"
  add_foreign_key "company_import_rows", "company_import_runs"
  add_foreign_key "company_import_rows", "company_proposals"
  add_foreign_key "company_logos", "companies"
  add_foreign_key "company_proposals", "admin_users"
  add_foreign_key "company_proposals", "companies"
  add_foreign_key "company_target_clients", "companies"
  add_foreign_key "company_target_clients", "target_clients"
  add_foreign_key "sub_categories", "categories"
  add_foreign_key "taggings", "companies"
  add_foreign_key "taggings", "tags"
end
