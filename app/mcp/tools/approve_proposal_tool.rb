module Mcp
  module Tools
    class ApproveProposalTool < BaseTool
      tool_name "approve_proposal"
      title "Approve proposal"
      description "Approve a proposal into a draft (publish=false) or publish it live (publish=true). Publishing is blocked by the quality gate and duplicate signals unless human_approved=true is passed (set only after a human approves in Slack)."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Approve proposal")
      input_schema(
        properties: {
          id: { type: "integer", description: "Proposal id." },
          publish: { type: "boolean", description: "Publish live (visible) if true; otherwise create an invisible draft. Default false." },
          human_approved: { type: "boolean", description: "Set true only when a human has approved this in Slack; overrides the auto-publish gate and kill-switch." },
          duplicate_override: { type: "boolean", description: "Approve despite duplicate signals (only honored together with human_approved)." }
        },
        required: ["id"]
      )

      def self.call(server_context:, id:, publish: false, human_approved: false, duplicate_override: false)
        proposal = CompanyProposal.find_by(id: id)
        return not_found("Proposal #{id} not found") unless proposal

        publish = ActiveModel::Type::Boolean.new.cast(publish)
        human_approved = ActiveModel::Type::Boolean.new.cast(human_approved)
        duplicate_override = ActiveModel::Type::Boolean.new.cast(duplicate_override)

        quality = CompanyProposalQualityService.call(proposal)
        gate_ok = quality["publish_ready"] && !proposal.duplicate_blocking?

        if publish && !gate_ok && !human_approved
          return error_response(
            "error" => "Publish blocked by quality gate. Fix blockers, resolve duplicates, or pass human_approved=true after a human approves.",
            "blockers" => quality["blockers"],
            "duplicate_blocking" => proposal.duplicate_blocking?,
            "admin_url" => admin_proposal_url(proposal)
          )
        end

        if publish && !Mcp::CuratorPolicy.autopublish_enabled? && !human_approved
          return error_response("error" => "Auto-publish is disabled (MCP_CURATOR_AUTOPUBLISH=false). A human must approve (human_approved=true).")
        end

        company = CompanyProposalApprovalService.call(
          proposal: proposal,
          admin_user: curator,
          publish: publish,
          duplicate_override: human_approved && duplicate_override
        )

        audit!(
          action: "approve_proposal",
          summary: "#{publish ? 'Published' : 'Drafted'} proposal #{id} -> company #{company.id}",
          records_processed: 1,
          details: { "proposal_id" => id, "company_id" => company.id, "published" => company.visible, "human_approved" => human_approved }
        )

        json_response(
          "proposal_id" => proposal.id,
          "status" => proposal.reload.status,
          "company_id" => company.id,
          "company_slug" => company.slug,
          "published" => company.visible,
          "profile_url" => (profile_url(company) if company.slug.present?),
          "admin_url" => admin_proposal_url(proposal)
        )
      rescue ArgumentError => e
        error_response("error" => e.message, "admin_url" => admin_proposal_url(proposal))
      end
    end
  end
end
