module Mcp
  module Tools
    class UpdateProposalTool < BaseTool
      tool_name "update_proposal"
      title "Update proposal"
      description "Set corrected values on a pending proposal before approval. Writes allowlisted company fields into the proposal's final_changes and returns a refreshed quality report. Use get_taxonomy for valid ids/tags. Descriptions must be neutral and public-ready: no marketing language, no internal notes, no remarks about missing information."
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
        proposal.save!
        quality = CompanyProposalQualityService.call(proposal)

        audit!(action: "update_proposal", summary: "Updated proposal #{id} fields: #{applied.keys.join(', ')}", records_processed: 1, details: { "proposal_id" => id, "fields" => applied.keys })

        json_response(
          "proposal_id" => proposal.id,
          "status" => proposal.status,
          "updated_fields" => applied.keys,
          "final_changes" => proposal.final_changes,
          "quality" => quality,
          "duplicate_blocking" => proposal.duplicate_blocking?,
          "admin_url" => admin_proposal_url(proposal)
        )
      rescue ActiveRecord::RecordInvalid => e
        error_response("error" => e.message)
      end
    end
  end
end
