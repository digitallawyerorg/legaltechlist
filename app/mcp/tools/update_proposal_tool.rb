module Mcp
  module Tools
    class UpdateProposalTool < BaseTool
      tool_name "update_proposal"
      title "Update proposal"
      # Setting any taxonomy field counts as a curator confirmation of the taxonomy,
      # which clears the "low-confidence taxonomy" quality blocker (previously only
      # re-running enrich_proposal could clear it).
      TAXONOMY_FIELDS = %w[category_id secondary_category_id business_model_id business_model_ids target_client_id target_client_ids].freeze

      description "Set corrected values on a pending proposal before approval. Writes allowlisted company fields into the proposal's final_changes and returns a refreshed quality report. Setting taxonomy fields (category/business model/target client) marks the taxonomy as curator-confirmed, clearing the low-confidence-taxonomy blocker. Use get_taxonomy for valid ids/tags. Descriptions must be neutral and public-ready: no marketing language, no internal notes, no remarks about missing information."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Update proposal")
      input_schema(
        properties: {
          id: { type: "integer", description: "Proposal id." },
          changes: { type: "object", description: "Company fields to set on the proposal.", properties: CHANGE_FIELD_SCHEMA, additionalProperties: false }
        },
        required: %w[id changes]
      )

      def self.call(server_context:, id:, changes:)
        proposal = CompanyProposal.find_by(id: id)
        return not_found("Proposal #{id} not found") unless proposal
        return error_response("error" => "Cannot edit a #{proposal.status} proposal.") if proposal.status.in?(%w[published rejected])

        applied = slice_editable_changes(changes)
        return error_response("error" => "No editable fields provided. Allowed: #{CompanyProposal::EDITABLE_COMPANY_FIELDS.join(', ')}") if applied.empty?

        proposal.final_changes = proposal.final_changes.merge(applied)
        taxonomy_confirmed = confirm_taxonomy!(proposal) if (applied.keys & TAXONOMY_FIELDS).any?
        proposal.save!
        quality = CompanyProposalQualityService.call(proposal)

        audit!(action: "update_proposal", summary: "Updated proposal #{id} fields: #{applied.keys.join(', ')}", records_processed: 1, details: { "proposal_id" => id, "fields" => applied.keys, "taxonomy_confirmed" => taxonomy_confirmed })

        json_response(
          "proposal_id" => proposal.id,
          "status" => proposal.status,
          "updated_fields" => applied.keys,
          "taxonomy_confirmed" => taxonomy_confirmed || false,
          "final_changes" => proposal.final_changes,
          "quality" => quality,
          "duplicate_blocking" => proposal.duplicate_blocking?,
          "admin_url" => admin_proposal_url(proposal)
        )
      rescue ActiveRecord::RecordInvalid => e
        error_response("error" => e.message)
      end

      def self.confirm_taxonomy!(proposal)
        suggestion = proposal.agent_details["taxonomy_suggestion"]
        suggestion = {} unless suggestion.is_a?(Hash)
        proposal.agent_details = proposal.agent_details.merge(
          "taxonomy_suggestion" => suggestion.merge("accepted" => true, "confirmed_by" => "curator", "confirmed_at" => Time.current.utc.iso8601)
        )
        true
      end
    end
  end
end
