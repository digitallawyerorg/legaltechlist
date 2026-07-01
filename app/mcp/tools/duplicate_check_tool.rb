module Mcp
  module Tools
    class DuplicateCheckTool < BaseTool
      tool_name "duplicate_check"
      title "Duplicate check"
      description "Check whether a company name/URL already exists in the visible index (name and canonical-domain matching)."
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, title: "Duplicate check")
      input_schema(
        properties: {
          name: { type: "string", description: "Company name to check." },
          url: { type: "string", description: "Company website URL (optional, improves domain matching)." }
        },
        required: ["name"]
      )

      def self.call(server_context:, name:, url: nil)
        normalized = AtlasCandidateNormalizerService.call("Organization Name" => name, "Website" => url)

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
