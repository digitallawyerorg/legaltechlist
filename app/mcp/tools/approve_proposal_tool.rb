module Mcp
  module Tools
    class ApproveProposalTool < BaseTool
      tool_name "approve_proposal"
      title "Approve proposal"
      description "Approve a proposal into a draft (publish=false) or publish it live (publish=true). Publish defaults to true when human_approved=true, and to false otherwise. Re-calling with publish=true on a proposal that was previously approved as an invisible draft promotes that draft to visible (no new company is created). To add a historical/already-acquired company in one step, pass status (e.g. \"acquired\", \"inactive\") so it publishes straight into that lifecycle state (never appearing as active), and/or an acquisition payload to record the acquirer at publish time. Publish live autonomously only when you are certain: the quality gate passes, there are no duplicate signals, and you pass a high confidence (>= the server threshold). Otherwise leave it for a human, or pass human_approved=true only after a human approves in Slack. Duplicate detection runs on every path, including a suggestion applied to an existing company: a blocking match stops the call, nothing is published or overwritten, and the record is routed to duplicate resolution (result=\"duplicate_resolution\")."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Approve proposal")
      input_schema(
        properties: {
          id: { type: "integer", description: "Proposal id." },
          publish: { type: "boolean", description: "Publish live (visible) if true; otherwise create an invisible draft. Defaults to true when human_approved=true, else false. Calling with publish=true promotes an existing invisible draft to visible." },
          confidence: { type: "number", description: "Your honest confidence (0.0-1.0) that this action is correct and well-sourced. Required to publish/apply autonomously; when unsure, leave it low and queue for a human instead." },
          human_approved: { type: "boolean", description: "Set true only when a human has approved this in Slack; overrides the auto-publish gate, kill-switch, and confidence threshold." },
          duplicate_override: { type: "boolean", description: "Approve despite duplicate signals (only honored together with human_approved)." },
          status: { type: "string", description: "Optional lifecycle status to publish into directly (e.g. \"acquired\", \"inactive\"), for adding historical entries without a transient active window. Defaults to \"acquired\" when an acquisition payload is supplied." },
          acquisition: {
            type: "object",
            description: "Optional: record an acquisition at publish time (implies status=acquired). The acquirer need not be in the index.",
            properties: {
              acquirer_name: { type: "string", description: "Acquiring company name (free text; required within the payload)." },
              acquirer_url: { type: "string", description: "Acquirer website (http(s))." },
              acquired_on: { type: "string", description: "Acquisition date as YYYY or YYYY-MM-DD." },
              successor_slug: { type: "string", description: "Slug/id of the acquirer's own TechIndex entry to link as successor." },
              source_url: { type: "string", description: "Citation URL for the acquisition." }
            }
          }
        },
        required: ["id"]
      )

      def self.call(server_context:, id:, publish: nil, confidence: nil, human_approved: false, duplicate_override: false, status: nil, acquisition: nil)
        proposal = CompanyProposal.find_by(id: id)
        return not_found("Proposal #{id} not found") unless proposal

        human_approved = ActiveModel::Type::Boolean.new.cast(human_approved)
        # publish defaults to human_approved's value when omitted: a human approval
        # implies intent to publish live, and the old always-false default silently
        # left proposals as invisible drafts in batch flows (an easy operator slip).
        publish = publish.nil? ? human_approved : ActiveModel::Type::Boolean.new.cast(publish)
        duplicate_override = ActiveModel::Type::Boolean.new.cast(duplicate_override)

        acquisition = (acquisition || {}).transform_keys(&:to_s).presence
        # An acquisition payload implies the entry is being published as acquired.
        target_status = status.presence || ("acquired" if acquisition)
        # Bake the lifecycle status into the proposal so the company is created with it
        # from the start — a historical/defunct entry never flashes as "active".
        proposal.final_changes = proposal.final_changes.merge("status" => target_status) if target_status.present?

        already = already_resolved_response(proposal, publish: publish)
        return already if already

        return apply_existing_company_update(proposal, id: id, publish: publish, confidence: confidence, human_approved: human_approved, duplicate_override: human_approved && duplicate_override) if proposal.user_suggestion?

        # Resolved before the quality report so both read the same answer, and so the
        # report's own duplicate blocker is not a second, staler opinion.
        duplicate = DuplicateGate.check(proposal)
        quality = CompanyProposalQualityService.call(proposal)
        gate_ok = quality["publish_ready"] && !duplicate.blocking?

        if publish && !gate_ok && !human_approved
          return error_response(
            "result" => "blocked",
            "published" => false,
            "error" => "Publish blocked by quality gate. Fix blockers, resolve duplicates, or pass human_approved=true after a human approves.",
            "publish_ready" => quality["publish_ready"],
            "blockers" => quality["blockers"],
            "duplicate_blocking" => duplicate.blocking?,
            "admin_url" => admin_proposal_url(proposal)
          )
        end

        if publish && !human_approved
          unless Mcp::CuratorPolicy.autopublish_enabled?
            return error_response("result" => "blocked", "published" => false, "error" => "Auto-publish is disabled (MCP_CURATOR_AUTOPUBLISH=false). A human must approve (human_approved=true).")
          end
          unless Mcp::CuratorPolicy.confidence_ok?(confidence, proposal)
            note = proposal.externally_submitted? ? " This is an external submission, so the bar is higher — only publish if you are sure it is a genuine legal-tech company (not spam/solicitation)." : ""
            return error_response("result" => "blocked", "published" => false, "error" => "Confidence below the autonomy threshold (#{Mcp::CuratorPolicy.required_confidence(proposal)}).#{note} Verify the entry and raise confidence, or leave it for a human.", "confidence" => confidence, "admin_url" => admin_proposal_url(proposal))
          end
        end

        company = CompanyProposalApprovalService.call(
          proposal: proposal,
          admin_user: curator,
          publish: publish,
          duplicate_override: human_approved && duplicate_override
        )

        # The company was created already carrying target_status (baked into
        # final_changes above), so it never appeared active. Now attach the acquirer
        # details (name/url/date/successor/source) in the same call.
        acquisition_applied = apply_acquisition(company, acquisition)

        audit!(
          action: "approve_proposal",
          summary: "#{publish ? 'Published' : 'Drafted'} proposal #{id} -> company #{company.id}#{" as #{company.status}" if company.status.present?}",
          records_processed: 1,
          details: { "proposal_id" => id, "company_id" => company.id, "published" => company.visible, "company_status" => company.status, "human_approved" => human_approved, "confidence" => confidence, "acquisition" => acquisition_applied }.compact
        )

        json_response(
          {
            "result" => (company.visible ? "published" : "drafted"),
            "published" => company.visible,
            "proposal_id" => proposal.id,
            "status" => proposal.reload.status,
            "company_status" => company.status,
            "company_id" => company.id,
            "company_slug" => company.slug,
            "acquisition" => acquisition_applied,
            "profile_url" => (profile_url(company) if company.slug.present?),
            "admin_url" => admin_proposal_url(proposal)
          }.compact
        )
      rescue DuplicateGate::Blocked => e
        # The gate routed the proposal to duplicate resolution rather than minting a
        # second row. Nothing was published; retrying will hit the same gate.
        error_response(
          "result" => "duplicate_resolution",
          "published" => false,
          "retryable" => false,
          "duplicate_blocking" => true,
          "error" => "#{e.message} Routed to duplicate resolution instead of approved; resolve it there, or re-approve with human_approved=true and duplicate_override=true if the records are genuinely different companies.",
          "admin_url" => admin_proposal_url(proposal)
        )
      rescue ArgumentError => e
        error_response("result" => "blocked", "published" => false, "retryable" => false, "error" => e.message, "admin_url" => admin_proposal_url(proposal))
      rescue StandardError => e
        # Unexpected/transient failure (e.g. an upstream or DB blip under load).
        # Signal the client may safely retry rather than treating it as terminal.
        Rails.logger.debug("[ApproveProposalTool] transient failure for proposal #{id}: #{e.class}: #{e.message}")
        error_response("result" => "error", "published" => false, "retryable" => true, "error" => "Transient failure (#{e.class}); safe to retry: #{e.message}", "admin_url" => admin_proposal_url(proposal))
      end

      # Attach acquirer details to a freshly-approved company when an acquisition
      # payload was supplied. Returns the applied hash (or nil). Raises ArgumentError
      # on invalid input so the caller reports a structured "blocked" response.
      def self.apply_acquisition(company, acquisition)
        return nil if acquisition.blank?

        successor_slug = acquisition["successor_slug"].presence
        successor = successor_slug ? find_company(successor_slug) : nil
        raise ArgumentError, "Successor '#{successor_slug}' not found" if successor_slug && successor.nil?

        CompanyAcquisitionService.call(
          company: company,
          acquirer_name: acquisition["acquirer_name"],
          acquirer_url: acquisition["acquirer_url"],
          acquired_on: acquisition["acquired_on"],
          successor: successor,
          source_url: acquisition["source_url"]
        ).applied
      end

      # Idempotent guard: never mint a second company for a proposal that already
      # produced one. Re-approval returns the existing company instead of creating
      # a duplicate record. Exception: an invisible draft + publish=true is NOT a
      # no-op — it falls through so the approval flow can promote the draft to
      # visible (recovering from an accidental publish=false approval).
      def self.already_resolved_response(proposal, publish: false)
        if proposal.user_suggestion?
          return nil unless proposal.status == "published" && proposal.company

          company = proposal.company
          return json_response("result" => "already_applied", "published" => company.visible, "proposal_id" => proposal.id, "company_id" => company.id, "company_slug" => company.slug, "profile_url" => (profile_url(company) if company.slug.present?), "applied_update" => true, "admin_url" => admin_proposal_url(proposal))
        end

        return nil if proposal.company_id.blank?

        company = proposal.company
        return nil if publish && !company.visible?

        json_response("result" => (company.visible ? "already_published" : "already_drafted"), "published" => company.visible, "proposal_id" => proposal.id, "company_id" => company.id, "company_slug" => company.slug, "profile_url" => (profile_url(company) if company.slug.present?), "admin_url" => admin_proposal_url(proposal))
      end

      # Apply an edit to an EXISTING company. This changes a live entry, so it
      # needs either an explicit human approval, or (when autoapply is enabled)
      # a high enough confidence to clear the autonomy threshold.
      def self.apply_existing_company_update(proposal, id:, publish:, confidence:, human_approved:, duplicate_override: false)
        autonomous_ok = Mcp::CuratorPolicy.autoapply_updates_enabled? && Mcp::CuratorPolicy.confidence_ok?(confidence, proposal)

        unless human_approved || autonomous_ok
          message = if !Mcp::CuratorPolicy.autoapply_updates_enabled?
            "Editing an existing company requires human_approved=true (autonomous edits are disabled: MCP_CURATOR_AUTOAPPLY_UPDATES=false)."
          else
            note = proposal.externally_submitted? ? " This is an external submission, so the bar is higher — only apply if you are sure the change is genuine (not spam/solicitation)." : ""
            "Confidence below the autonomy threshold (#{Mcp::CuratorPolicy.required_confidence(proposal)}) for editing a live company.#{note} Verify the change and raise confidence, or wait for human approval."
          end
          return error_response("result" => "blocked", "published" => false, "applied_update" => false, "error" => message, "confidence" => confidence, "admin_url" => admin_proposal_url(proposal))
        end

        company = CompanyProposalApplyUpdateService.call(proposal: proposal, admin_user: curator, publish: publish, duplicate_override: duplicate_override)

        audit!(
          action: "approve_proposal",
          summary: "Applied update proposal #{id} to company #{company.id}",
          records_processed: 1,
          details: { "proposal_id" => id, "company_id" => company.id, "applied_update" => true, "human_approved" => human_approved, "confidence" => confidence, "autonomous" => !human_approved }
        )

        json_response(
          "result" => "update_applied",
          "applied_update" => true,
          "published" => company.visible,
          "proposal_id" => proposal.id,
          "status" => proposal.reload.status,
          "company_id" => company.id,
          "company_slug" => company.slug,
          "profile_url" => (profile_url(company) if company.slug.present?),
          "admin_url" => admin_proposal_url(proposal)
        )
      rescue DuplicateGate::Blocked => e
        # Not applied and not published: the gate routed the suggestion to duplicate
        # resolution, where the record it actually collides with can be compared against
        # it. Reported separately from a plain block so the caller does not retry.
        error_response(
          "result" => "duplicate_resolution",
          "published" => false,
          "applied_update" => false,
          "retryable" => false,
          "duplicate_blocking" => true,
          "error" => "#{e.message} Routed to duplicate resolution instead of applied; resolve it there, or re-approve with human_approved=true and duplicate_override=true if the records are genuinely different companies.",
          "admin_url" => admin_proposal_url(proposal)
        )
      rescue ArgumentError => e
        error_response("result" => "blocked", "published" => false, "applied_update" => false, "retryable" => false, "error" => e.message, "admin_url" => admin_proposal_url(proposal))
      rescue StandardError => e
        Rails.logger.debug("[ApproveProposalTool] transient failure applying update proposal #{id}: #{e.class}: #{e.message}")
        error_response("result" => "error", "published" => false, "applied_update" => false, "retryable" => true, "error" => "Transient failure (#{e.class}); safe to retry: #{e.message}", "admin_url" => admin_proposal_url(proposal))
      end
    end
  end
end
