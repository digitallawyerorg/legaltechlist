module Mcp
  module Tools
    # Make an approved draft public without re-approving it.
    #
    # Approving a proposal creates the company hidden; publication was only reachable by
    # approving again, which the duplicate gate then blocked because the draft from the
    # first approval already existed. Eleven approved records sat invisible with 404
    # pages for exactly that reason, and the only remaining route was a second approval
    # that would have minted a duplicate.
    class PublishCompanyTool < BaseTool
      tool_name "publish_company"
      title "Publish an approved company draft"
      description "Make an existing but hidden company visible on the public site. Use this for a record that was approved as a draft and never went live — it does not re-run approval, so it cannot mint a duplicate. Publication still requires the record to pass the same publish gate as any approval, and human_approved=true is required because this puts a page in front of the public. Pass hidden_only=false to no-op safely on an already-visible record."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true, title: "Publish company draft")
      input_schema(
        properties: {
          slug: { type: "string", description: "Company slug or numeric id." },
          human_approved: { type: "boolean", description: "Required. Confirms a human authorised making this record public." },
          reason: { type: "string", description: "Why it is being published now, recorded on the record." }
        },
        required: %w[slug human_approved]
      )

      def self.call(server_context:, slug:, human_approved: false, reason: nil)
        company = find_company(slug)
        return not_found("Company '#{slug}' not found") unless company
        return json_response("result" => "already_visible", "company_id" => company.id, "published" => true, "profile_url" => profile_url(company)) if company.visible?

        unless ActiveModel::Type::Boolean.new.cast(human_approved)
          return error_response("result" => "blocked", "retryable" => false, "error" => "Publishing puts a page in front of the public and requires human_approved=true.")
        end

        blockers = publish_blockers(company)
        if blockers.any?
          return error_response("result" => "blocked", "retryable" => false, "error" => "Resolve these before publishing: #{blockers.to_sentence}", "company_id" => company.id)
        end

        company.update!(visible: true, quality_reviewed_at: Time.current)
        record_publication!(company, reason: reason)
        audit!(action: "publish_company", summary: "Published #{company.name}", records_processed: 1,
               details: { "company_id" => company.id, "reason" => reason })

        json_response("result" => "published", "company_id" => company.id, "published" => true,
                      "profile_url" => profile_url(company), "company_slug" => company.slug)
      end

      # The same conditions a proposal approval would enforce, applied to the record
      # itself: it must be presentable and it must not be a duplicate of a live entry.
      def self.publish_blockers(company)
        blockers = []
        blockers << "it was taken off the site on purpose (#{company.verification_verdict.presence || company.quality_status}); reopen it with mark_review verified or needs_work first" if company.deliberately_hidden?
        blockers << "it has no description" if company.description.to_s.strip.blank?
        blockers << "it has no website" if company.main_url.to_s.strip.blank?
        blockers << "its description does not clear the publication gate" unless description_ok?(company)
        duplicates = Company.duplicates_by_domain_for(company).where(visible: true)
        blockers << "#{duplicates.first.name} (##{duplicates.first.id}) is already public on the same domain" if duplicates.any?
        blockers
      end

      def self.description_ok?(company)
        return false if company.description.to_s.strip.blank?

        CompanyProposalEnrichmentService.description_critic_for(company.description)["verdict"] == "pass"
      end

      def self.record_publication!(company, reason:)
        review = company.quality_review.is_a?(Hash) ? company.quality_review.deep_dup : {}
        review["publications"] = Array(review["publications"]) + [{
          "at" => Time.current.utc.iso8601, "via" => "publish_company", "reason" => reason.to_s.strip.presence
        }]
        company.update_columns(quality_review: review)
      end
    end
  end
end
