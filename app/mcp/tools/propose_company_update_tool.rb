module Mcp
  module Tools
    class ProposeCompanyUpdateTool < BaseTool
      tool_name "propose_company_update"
      title "Propose company update"
      description "Create a review proposal that edits an existing company (e.g. fix a stale URL, correct classification, or record an acquisition/merger or a change to acquired/defunct status). This does NOT change the live entry: it queues a proposal that a human must approve (approve_proposal with human_approved=true). Use get_taxonomy for valid ids/tags and keep any description neutral and public-ready."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Propose company update")
      input_schema(
        properties: {
          slug: { type: "string", description: "Company slug or numeric id." },
          changes: { type: "object", description: "Company fields to change.", properties: CHANGE_FIELD_SCHEMA, additionalProperties: false },
          rationale: { type: "string", description: "Why this change is needed, with evidence/source. Shown to the human reviewer." }
        },
        required: %w[slug changes]
      )

      def self.call(server_context:, slug:, changes:, rationale: nil)
        company = find_company(slug)
        return not_found("Company '#{slug}' not found") unless company

        applied = slice_editable_changes(changes)
        return error_response("error" => "No editable fields provided. Allowed: #{CompanyProposal::EDITABLE_COMPANY_FIELDS.join(', ')}") if applied.empty?

        proposal = CompanyProposal.create!(
          proposal_type: "user_suggestion",
          status: "ready_for_review",
          source: "claude_tag_curator",
          source_identifier: "curator-update-#{company.id}-#{Time.current.to_i}-#{SecureRandom.hex(3)}",
          company: company,
          admin_user: curator,
          issue_type: "curator_update",
          proposed_changes: applied,
          final_changes: applied,
          user_message: rationale.to_s,
          reviewer_notes: rationale.to_s
        )

        audit!(action: "propose_company_update", summary: "Proposed update to #{company.name} (##{company.id}) fields: #{applied.keys.join(', ')}", records_processed: 1, details: { "company_id" => company.id, "proposal_id" => proposal.id, "fields" => applied.keys })

        json_response(
          "proposal_id" => proposal.id,
          "company_id" => company.id,
          "company_slug" => company.slug,
          "status" => proposal.status,
          "proposed_changes" => applied,
          "note" => "Awaiting human approval. Apply with approve_proposal(id: #{proposal.id}, human_approved: true).",
          "admin_url" => admin_proposal_url(proposal)
        )
      rescue ActiveRecord::RecordInvalid => e
        error_response("error" => e.message)
      end
    end
  end
end
