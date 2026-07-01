module Mcp
  module Tools
    class ApplySafeFieldsTool < BaseTool
      # Mirror of Admin::AgentReviewsController::SAFE_APPLY_FIELDS: the only fields a
      # curator may write directly on an existing company.
      SAFE_FIELDS = %w[quality_status verification_verdict quality_score canonical_domain fingerprint].freeze

      tool_name "apply_safe_fields"
      title "Apply safe fields"
      description "Apply a restricted allowlist of review fields to an existing company: #{SAFE_FIELDS.join(', ')}. No other company fields can be changed through this tool."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true, title: "Apply safe fields")
      input_schema(
        properties: {
          slug: { type: "string", description: "Company slug or numeric id." },
          fields: {
            type: "object",
            description: "Map of safe fields to values.",
            properties: {
              quality_status: { type: "string" },
              verification_verdict: { type: "string" },
              quality_score: { type: "integer" },
              canonical_domain: { type: "string" },
              fingerprint: { type: "string" }
            },
            additionalProperties: false
          }
        },
        required: ["slug", "fields"]
      )

      def self.call(server_context:, slug:, fields:)
        company = find_company(slug)
        return not_found("Company '#{slug}' not found") unless company

        applied = (fields || {}).transform_keys(&:to_s).slice(*SAFE_FIELDS)
        return not_found("No safe fields provided. Allowed: #{SAFE_FIELDS.join(', ')}") if applied.empty?

        applied["quality_score"] = applied["quality_score"].to_i if applied.key?("quality_score") && applied["quality_score"].present?
        applied.each { |field, value| company.public_send("#{field}=", value) }
        company.save!

        audit!(action: "apply_safe_fields", summary: "Applied #{applied.keys.join(', ')} to #{company.name}", records_processed: 1, details: { "company_id" => company.id, "applied" => applied })

        json_response("company_slug" => company.slug, "applied" => applied)
      rescue ActiveRecord::RecordInvalid => e
        error_response("error" => e.message)
      end
    end
  end
end
