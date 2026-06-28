module TaxonomyCompleteness
  extend ActiveSupport::Concern

  TAXONOMY_FIELD_KEYS = %w[category_id business_model_id target_client_id].freeze

  class_methods do
    def proposal_missing_taxonomy_scope
      pending_review.where(
        <<~SQL.squish
          COALESCE(final_changes->>'category_id', '') = ''
          OR (
            COALESCE(final_changes->>'business_model_id', '') = ''
            AND COALESCE(jsonb_array_length(final_changes->'business_model_ids'), 0) = 0
          )
          OR (
            COALESCE(final_changes->>'target_client_id', '') = ''
            AND COALESCE(jsonb_array_length(final_changes->'target_client_ids'), 0) = 0
          )
        SQL
      )
    end
  end

  def revenue_models_present?(changes = editable_changes)
    Array(changes["business_model_ids"]).map(&:presence).compact.any? || changes["business_model_id"].present?
  end

  def target_clients_present?(changes = editable_changes)
    Array(changes["target_client_ids"]).map(&:presence).compact.any? || changes["target_client_id"].present?
  end

  def missing_taxonomy_field_keys(changes = editable_changes)
    keys = []
    keys << "category_id" if changes["category_id"].blank?
    keys << "business_model_id" unless revenue_models_present?(changes)
    keys << "target_client_id" unless target_clients_present?(changes)
    keys
  end
end
