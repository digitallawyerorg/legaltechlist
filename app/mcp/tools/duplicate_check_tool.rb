module Mcp
  module Tools
    class DuplicateCheckTool < BaseTool
      tool_name "duplicate_check"
      title "Duplicate check"
      description "Check whether a company name/URL already exists in the index, published or as an unpublished draft (name and canonical-domain matching). Each match reports `visible`, so a hidden draft from an earlier approval is distinguishable from a live entry — approving over one of those is what creates duplicates."
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, title: "Duplicate check")
      input_schema(
        properties: {
          name: { type: "string", description: "Company name to check." },
          url: { type: "string", description: "Company website URL (optional, improves domain matching)." },
          exclude_id: { type: "integer", description: "A company id to leave out of the matches: pass the record you are renaming, so it is not reported as its own duplicate." }
        },
        required: ["name"]
      )

      def self.call(server_context:, name:, url: nil, exclude_id: nil)
        normalized = AtlasCandidateNormalizerService.call("Organization Name" => name, "Website" => url)
        if exclude_id.present?
          %w[name_matches domain_matches].each do |key|
            normalized[key] = Array(normalized[key]).reject { |match| match.is_a?(Hash) && (match["id"] || match[:id]).to_i == exclude_id.to_i }
          end
          normalized["recommended_action"] = "No other record matches (company ##{exclude_id.to_i} excluded)." if normalized["name_matches"].empty? && normalized["domain_matches"].empty?
        end

        json_response(
          "name" => normalized["name"],
          "canonical_domain" => normalized["canonical_domain"],
          "status" => normalized["status"],
          "name_matches" => normalized["name_matches"],
          "domain_matches" => normalized["domain_matches"],
          "recommended_action" => normalized["recommended_action"]
        )
      end
    end
  end
end
