module Mcp
  module Tools
    # In-place edit of a small allowlist of SAFE FACTUAL fields on an existing
    # (typically published) company, so a backfilled value (e.g. a sourced founding
    # year) lands on the live profile in a single call — without unpublishing or a
    # separate human-approved suggestion. Editorial changes (e.g. description) must
    # still go through propose_company_update.
    class UpdateCompanyFieldTool < BaseTool
      FACT_FIELDS = %w[founded_date location founders status].freeze

      tool_name "update_company_field"
      title "Update company factual field"
      description "Edit safe factual fields (#{FACT_FIELDS.join(', ')}) directly on an existing/published company so a backfilled value lands on the live profile in one call. founded_date must be a plausible 4-digit year and REQUIRES a source_url (cite-only — never guess a year). Use propose_company_update for editorial changes or anything outside this allowlist."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true, title: "Update company factual field")
      input_schema(
        properties: {
          slug: { type: "string", description: "Company slug or numeric id." },
          fields: {
            type: "object",
            description: "Factual fields to set.",
            properties: {
              founded_date: { type: "string", description: "4-digit founding year (requires source_url)." },
              location: { type: "string" },
              founders: { type: "string" },
              status: { type: "string", description: "Lifecycle status, e.g. active, acquired, defunct." }
            },
            additionalProperties: false
          },
          source_url: { type: "string", description: "Citation URL supporting the value; required when setting founded_date." }
        },
        required: %w[slug fields]
      )

      def self.call(server_context:, slug:, fields:, source_url: nil)
        company = find_company(slug)
        return not_found("Company '#{slug}' not found") unless company

        applied = (fields || {}).transform_keys(&:to_s).slice(*FACT_FIELDS).compact
        return not_found("No factual fields provided. Allowed: #{FACT_FIELDS.join(', ')}") if applied.empty?

        if applied["founded_date"].present?
          year = applied["founded_date"].to_s.strip
          return error_response("result" => "blocked", "retryable" => false, "error" => "founded_date must be a plausible 4-digit year (1970-#{Date.current.year}).") unless plausible_year?(year)
          return error_response("result" => "blocked", "retryable" => false, "error" => "founded_date requires a source_url citation (cite-only — never guess a founding year).") unless valid_http_url?(source_url)
        end

        other_fields = applied.except("founded_date")
        other_fields.each { |field, value| company.public_send("#{field}=", value) }
        company.save! if other_fields.any?
        company.founded_date_from_source!(year: applied["founded_date"], source_url: source_url) if applied["founded_date"].present?

        audit!(action: "update_company_field", summary: "Updated #{applied.keys.join(', ')} on #{company.name}", records_processed: 1, details: { "company_id" => company.id, "applied" => applied, "source_url" => source_url })

        json_response(
          "result" => "updated",
          "company_id" => company.id,
          "company_slug" => company.slug,
          "applied" => applied,
          "source_url" => source_url,
          "company" => company_summary(company)
        )
      rescue ActiveRecord::RecordInvalid => e
        error_response("result" => "blocked", "retryable" => false, "error" => e.message)
      rescue StandardError => e
        Rails.logger.debug("[UpdateCompanyFieldTool] transient failure for #{slug}: #{e.class}: #{e.message}")
        error_response("result" => "error", "retryable" => true, "error" => "Transient failure (#{e.class}); safe to retry: #{e.message}")
      end

      def self.plausible_year?(value)
        value.to_s.strip.match?(/\A(?:19|20)\d{2}\z/) && (1970..Date.current.year).cover?(value.to_s.strip.to_i)
      end

      def self.valid_http_url?(value)
        uri = URI.parse(value.to_s.strip)
        uri.is_a?(URI::HTTP) && uri.host.present?
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
