module Mcp
  module Tools
    # Merge duplicate directory entries into one canonical survivor. This is the real
    # resolution for a list_duplicate_candidates pair: pick the clean-identity record as
    # the keeper and fold the other(s) in — blank keeper fields are filled from the
    # duplicates (e.g. funding data), all associations (tags, business models, target
    # clients, proposals, import rows, attachments) transfer to the keeper, any successor
    # references are repointed, and the duplicates are deleted. Merging is DESTRUCTIVE, so
    # it previews by default and only executes when authorized (human_approved or a
    # confidence at/above the server threshold).
    class MergeCompaniesTool < BaseTool
      tool_name "merge_companies"
      title "Merge duplicate companies"
      description "Merge duplicate entries into one canonical survivor (the real fix for a list_duplicate_candidates pair). Pass keep_id (the survivor to keep) and merge_ids (the duplicate ids to fold in and delete). Blank keeper fields are filled from the duplicates (identity stays the keeper's; gaps like funding data get folded), all associations transfer to the keeper, successor references are repointed, and the duplicates are deleted so the pair drops out of the dup queue. DESTRUCTIVE: it returns a dry-run PREVIEW (filled_fields + transferred_associations, nothing deleted) unless you authorize it with human_approved=true (after a human review) or a confidence at/above the server threshold. Refuses to delete a duplicate that is itself acquired or has a successor link (keep that record instead, or record the acquisition first)."
      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: false, title: "Merge duplicate companies")
      input_schema(
        properties: {
          keep_id: { type: "integer", description: "Company id of the survivor to keep (the canonical record). Its non-blank fields win; only its blank fields are filled from the duplicates." },
          merge_ids: { type: "array", items: { type: "integer" }, description: "Company id(s) of the duplicate(s) to fold into the keeper and delete." },
          confidence: { type: "number", description: "Your honest confidence (0.0-1.0) that these are the same company and the merge is correct. Required to execute autonomously; below the threshold you get a preview instead." },
          human_approved: { type: "boolean", description: "Set true only when a human has confirmed the merge; executes regardless of the confidence threshold." },
          dry_run: { type: "boolean", description: "Force a preview only (no deletion), even when authorized. Defaults false; note that without authorization the tool previews anyway." }
        },
        required: %w[keep_id merge_ids]
      )

      def self.call(server_context:, keep_id:, merge_ids:, confidence: nil, human_approved: false, dry_run: false)
        keeper = Company.find_by(id: keep_id)
        return not_found("Keeper company #{keep_id} not found") unless keeper

        duplicate_ids = Array(merge_ids).map(&:to_i).uniq - [keeper.id]
        return error_response("result" => "blocked", "retryable" => false, "error" => "No valid merge_ids (must differ from keep_id).") if duplicate_ids.empty?

        human_approved = ActiveModel::Type::Boolean.new.cast(human_approved)
        dry_run = ActiveModel::Type::Boolean.new.cast(dry_run)
        authorized = human_approved || Mcp::CuratorPolicy.confidence_ok?(confidence)
        preview_only = dry_run || !authorized

        result = CompanyDuplicateConsolidationService.merge_into(
          keep_id: keeper.id,
          merge_ids: duplicate_ids,
          reviewer: "claude_tag",
          dry_run: preview_only
        )

        if result["result"] == "blocked"
          return error_response(result.merge("retryable" => false, "error" => block_message(result["reason"])))
        end

        if preview_only
          reason = dry_run ? "dry_run requested" : "requires authorization (pass human_approved=true or confidence >= #{Mcp::CuratorPolicy.min_confidence})"
          return json_response(result.merge("requires_confirmation" => !dry_run, "note" => "Preview only — nothing was deleted (#{reason}). Re-call with human_approved=true or a sufficient confidence to execute."))
        end

        audit!(
          action: "merge_companies",
          summary: "Merged #{result['deleted_company_ids'].join(', ')} into #{keeper.name} (##{keeper.id})",
          records_processed: result["deleted_company_ids"].size,
          details: { "keeper_id" => keeper.id, "deleted_company_ids" => result["deleted_company_ids"], "human_approved" => human_approved, "confidence" => confidence, "filled_fields" => result["filled_fields"] }
        )

        json_response(result.merge("company" => company_summary(keeper.reload), "profile_url" => profile_url(keeper)))
      rescue ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
        # A constraint failure is a defect in the merge, not a blip: retrying repeats it.
        # The merge runs in one transaction, so nothing was changed.
        error_response("result" => "error", "retryable" => false, "error" => "Merge rolled back, nothing changed (#{e.class}): #{e.message}")
      rescue StandardError => e
        Rails.logger.debug("[MergeCompaniesTool] transient failure merging into #{keep_id}: #{e.class}: #{e.message}")
        error_response("result" => "error", "retryable" => true, "error" => "Transient failure (#{e.class}); safe to retry: #{e.message}")
      end

      def self.block_message(reason)
        case reason
        when "keeper_not_found" then "Keeper company not found."
        when "no_valid_duplicates" then "No valid duplicates to merge (they must exist and differ from the keeper)."
        when "acquired_duplicate" then "A duplicate to be deleted is marked acquired — merging would lose its acquisition data. Make that record the keeper instead, or record the acquisition first."
        when "duplicate_has_successor_link" then "A duplicate to be deleted has a successor link — merging would lose it. Make that record the keeper instead."
        else "Merge blocked: #{reason}."
        end
      end
    end
  end
end
