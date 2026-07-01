module Mcp
  module Tools
    class ApproveProposalTool < BaseTool
      tool_name "approve_proposal"
      title "Approve proposal"
      description "Approve a proposal into a draft (publish=false) or publish it live (publish=true). Publish live autonomously only when you are certain: the quality gate passes, there are no duplicate signals, and you pass a high confidence (>= the server threshold). Otherwise leave it for a human, or pass human_approved=true only after a human approves in Slack."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Approve proposal")
      input_schema(
        properties: {
          id: { type: "integer", description: "Proposal id." },
          publish: { type: "boolean", description: "Publish live (visible) if true; otherwise create an invisible draft. Default false." },
          confidence: { type: "number", description: "Your honest confidence (0.0-1.0) that this action is correct and well-sourced. Required to publish/apply autonomously; when unsure, leave it low and queue for a human instead." },
          human_approved: { type: "boolean", description: "Set true only when a human has approved this in Slack; overrides the auto-publish gate, kill-switch, and confidence threshold." },
          duplicate_override: { type: "boolean", description: "Approve despite duplicate signals (only honored together with human_approved)." }
        },
        required: ["id"]
      )

      def self.call(server_context:, id:, publish: false, confidence: nil, human_approved: false, duplicate_override: false)
        proposal = CompanyProposal.find_by(id: id)
        return not_found("Proposal #{id} not found") unless proposal

        publish = ActiveModel::Type::Boolean.new.cast(publish)
        human_approved = ActiveModel::Type::Boolean.new.cast(human_approved)
        duplicate_override = ActiveModel::Type::Boolean.new.cast(duplicate_override)

        return apply_existing_company_update(proposal, id: id, publish: publish, confidence: confidence, human_approved: human_approved) if proposal.user_suggestion?

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

        if publish && !human_approved
          unless Mcp::CuratorPolicy.autopublish_enabled?
            return error_response("error" => "Auto-publish is disabled (MCP_CURATOR_AUTOPUBLISH=false). A human must approve (human_approved=true).")
          end
          unless Mcp::CuratorPolicy.confidence_ok?(confidence)
            return error_response("error" => "Confidence below the autonomy threshold (#{Mcp::CuratorPolicy.min_confidence}). Improve/verify the entry and raise confidence, or leave it for a human.", "confidence" => confidence, "admin_url" => admin_proposal_url(proposal))
          end
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
          details: { "proposal_id" => id, "company_id" => company.id, "published" => company.visible, "human_approved" => human_approved, "confidence" => confidence }
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

      # Apply an edit to an EXISTING company. This changes a live entry, so it
      # needs either an explicit human approval, or (when autoapply is enabled)
      # a high enough confidence to clear the autonomy threshold.
      def self.apply_existing_company_update(proposal, id:, publish:, confidence:, human_approved:)
        autonomous_ok = Mcp::CuratorPolicy.autoapply_updates_enabled? && Mcp::CuratorPolicy.confidence_ok?(confidence)

        unless human_approved || autonomous_ok
          message = if !Mcp::CuratorPolicy.autoapply_updates_enabled?
            "Editing an existing company requires human_approved=true (autonomous edits are disabled: MCP_CURATOR_AUTOAPPLY_UPDATES=false)."
          else
            "Confidence below the autonomy threshold (#{Mcp::CuratorPolicy.min_confidence}) for editing a live company. Verify the change and raise confidence, or wait for human approval."
          end
          return error_response("error" => message, "confidence" => confidence, "admin_url" => admin_proposal_url(proposal))
        end

        company = CompanyProposalApplyUpdateService.call(proposal: proposal, admin_user: curator, publish: publish)

        audit!(
          action: "approve_proposal",
          summary: "Applied update proposal #{id} to company #{company.id}",
          records_processed: 1,
          details: { "proposal_id" => id, "company_id" => company.id, "applied_update" => true, "human_approved" => human_approved, "confidence" => confidence, "autonomous" => !human_approved }
        )

        json_response(
          "proposal_id" => proposal.id,
          "status" => proposal.reload.status,
          "company_id" => company.id,
          "company_slug" => company.slug,
          "published" => company.visible,
          "profile_url" => (profile_url(company) if company.slug.present?),
          "admin_url" => admin_proposal_url(proposal),
          "applied_update" => true
        )
      rescue ArgumentError => e
        error_response("error" => e.message, "admin_url" => admin_proposal_url(proposal))
      end
    end
  end
end
