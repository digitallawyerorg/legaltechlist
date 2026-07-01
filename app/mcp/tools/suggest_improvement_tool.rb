module Mcp
  module Tools
    class SuggestImprovementTool < BaseTool
      tool_name "suggest_improvement"
      title "Suggest improvement"
      description "Record a suggestion for improving the TechIndex or the curator tooling/workflow — e.g. a missing tool, a recurring data problem, or an unclear guideline that makes curation harder. The suggestion is logged for maintainers and posted to Slack. It does not change any company data."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Suggest improvement")
      input_schema(
        properties: {
          suggestion: { type: "string", description: "The improvement idea, described clearly and specifically." },
          area: { type: "string", description: "Optional area, e.g. tooling, taxonomy, data-quality, workflow, discovery." }
        },
        required: %w[suggestion]
      )

      def self.call(server_context:, suggestion:, area: nil)
        text = suggestion.to_s.strip
        return error_response("error" => "suggestion cannot be blank") if text.blank?

        run = audit!(action: "suggest_improvement", summary: text.truncate(140), records_processed: 0, details: { "area" => area, "suggestion" => text })
        SlackNotifier.curator_improvement(text, area: area)

        json_response("recorded" => true, "pipeline_run_id" => run&.id, "area" => area)
      end
    end
  end
end
