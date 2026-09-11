module Mcp
  module Tools
    # In-place edit of a small allowlist of fields on an existing (typically published)
    # company, so a correction lands on the live profile in a single call.
    #
    # description was excluded here until it became the thing most often needing repair:
    # an enrichment that overwrote a submitter's text left no tool able to put it back,
    # and the fix required engineering every time. It is writable now, but only through
    # the same deterministic gate every published description passes, with a mandatory
    # reason recorded, and it sets a lock so the next enrichment cannot silently undo the
    # repair — which is exactly how the SpecterAI restore was lost in August.
    class UpdateCompanyFieldTool < BaseTool
      FACT_FIELDS = %w[founded_date location founders status country city].freeze
      TEXT_FIELDS = %w[description main_url linkedin_url crunchbase_url name].freeze
      # Taxonomy an enrichment can get wrong and nothing could then put right: tags were
      # unreachable, and a wrongly-set secondary category could not be cleared at all.
      TAXONOMY_FIELDS = %w[all_tags secondary_category_id].freeze
      WRITABLE_FIELDS = (FACT_FIELDS + TEXT_FIELDS + TAXONOMY_FIELDS).freeze

      tool_name "update_company_field"
      title "Update company factual field"
      description "Edit an existing/published company in place: #{WRITABLE_FIELDS.join(', ')}. founded_date must be a plausible 4-digit year and REQUIRES a source_url (cite-only — never guess a year). Writing description or a url REQUIRES a `reason` (e.g. 'restoring the submitter's original text after an enrichment overwrote it'); a description must clear the same publication gate as any published text, and writing one locks the record against further automated description changes until a human unlocks it. Use propose_company_update for anything outside this allowlist."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true, title: "Update company factual field")
      input_schema(
        properties: {
          slug: { type: "string", description: "Company slug or numeric id." },
          fields: {
            type: "object",
            description: "Factual fields to set.",
            properties: {
              founded_date: { type: "string", description: "4-digit founding year (requires source_url)." },
              location: { type: "string" },
              founders: { type: "string" },
              status: { type: "string", description: "Lifecycle status, e.g. active, acquired, defunct." },
              country: { type: "string", description: "Country as an official source states it." },
              city: { type: "string", description: "City or locality." },
              name: { type: "string", description: "Company or legal entity name. Requires reason; changes the record identity, so check for duplicates first." },
              description: { type: "string", description: "Public description. Must clear the publication gate; requires reason." },
              main_url: { type: "string", description: "Primary website. Requires reason." },
              linkedin_url: { type: "string", description: "LinkedIn company URL. Requires reason." },
              crunchbase_url: { type: "string", description: "Crunchbase URL. Requires reason." },
              all_tags: { type: "string", description: "Comma-separated tag list, replacing the current tags. Requires reason." },
              secondary_category_id: { type: %w[integer string null], description: "Secondary category id, or null/empty to clear it. Requires reason." }
            },
            additionalProperties: false
          },
          source_url: { type: "string", description: "Citation URL supporting the value; required when setting founded_date." },
          reason: { type: "string", description: "Why this edit is being made. Required for description and url fields, and recorded on the company." },
          lock_description: { type: "boolean", description: "Default true when writing a description: stops later automated enrichment overwriting it. Pass false only when the record should stay open to enrichment." }
        },
        required: %w[slug fields]
      )

      def self.call(server_context:, slug:, fields:, source_url: nil, reason: nil, lock_description: nil)
        company = find_company(slug)
        return not_found("Company '#{slug}' not found") unless company

        raw = (fields || {}).transform_keys(&:to_s).slice(*WRITABLE_FIELDS)
        # An explicit null clears secondary_category_id, so it must survive `compact`.
        clearing = raw.key?("secondary_category_id") && raw["secondary_category_id"].blank?
        applied = raw.compact
        applied["secondary_category_id"] = nil if clearing
        return not_found("No writable fields provided. Allowed: #{WRITABLE_FIELDS.join(', ')}") if applied.empty?

        # An edit to public text has to say why. Without it there is no way for the next
        # reader to tell a considered restore from an accident.
        blanked = applied.slice(*TEXT_FIELDS, *FACT_FIELDS).select { |_field, value| value.to_s.strip.blank? }
        if blanked.any?
          return error_response("result" => "blocked", "retryable" => false, "error" => "Refusing to blank #{blanked.keys.to_sentence}. Send a value, or use secondary_category_id: null if you meant to clear a category.")
        end

        text_edits = applied.slice(*TEXT_FIELDS, *TAXONOMY_FIELDS)
        if text_edits.any? && reason.to_s.strip.blank?
          return error_response("result" => "blocked", "retryable" => false, "error" => "Editing #{text_edits.keys.to_sentence} requires a `reason` explaining the change.")
        end

        if applied["description"].present?
          verdict = CompanyProposalEnrichmentService.description_critic_for(applied["description"])
          unless verdict["verdict"] == "pass"
            issues = Array(verdict["issues"]).to_sentence.presence
            return error_response("result" => "blocked", "retryable" => false, "error" => "That description does not clear the publication gate#{" (#{issues})" if issues}.")
          end
        end

        %w[main_url linkedin_url crunchbase_url].each do |url_field|
          next if applied[url_field].blank?
          return error_response("result" => "blocked", "retryable" => false, "error" => "#{url_field} must be an http(s) URL.") unless valid_http_url?(applied[url_field])
        end

        if applied["founded_date"].present?
          year = applied["founded_date"].to_s.strip
          return error_response("result" => "blocked", "retryable" => false, "error" => "founded_date must be a plausible 4-digit year (1970-#{Date.current.year}).") unless plausible_year?(year)
          return error_response("result" => "blocked", "retryable" => false, "error" => "founded_date requires a source_url citation (cite-only — never guess a founding year).") unless valid_http_url?(source_url)
        end

        previous = applied.keys.index_with { |field| company.public_send(field) }

        other_fields = applied.except("founded_date")
        other_fields.each { |field, value| company.public_send("#{field}=", value) }
        rejected_tags = []
        if applied.key?("all_tags")
          company.all_tags = applied["all_tags"]
          rejected_tags = Array(company.rejected_tag_names)
        end
        company.canonical_domain = company.canonical_main_domain if applied.key?("main_url")
        # Identity keys are derived, so a name or url change has to rebuild them or the
        # duplicate detector keeps matching on the old value.
        company.fingerprint = company.calculated_fingerprint if applied.key?("main_url") || applied.key?("name")
        record_edit!(company, applied: applied, previous: previous, reason: reason, lock: lock_description)
        company.save! if other_fields.any?
        company.founded_date_from_source!(year: applied["founded_date"], source_url: source_url) if applied["founded_date"].present?

        # Read back rather than reported back. Until now this returned the values it had
        # been asked to write, which is an echo of the request and not evidence that the
        # database accepted it — a rejected tag, a validation that silently dropped a
        # value, or a save that never ran all reported "updated" just the same.
        company.reload
        confirmed, unconfirmed = confirm_saved(company, applied)
        result = if unconfirmed.empty?
          "updated"
        elsif confirmed.empty?
          "not_saved"
        else
          "partially_updated"
        end

        audit!(action: "update_company_field", summary: "Updated #{confirmed.keys.join(', ').presence || 'nothing'} on #{company.name}", records_processed: 1, details: { "company_id" => company.id, "requested" => applied, "confirmed" => confirmed, "unconfirmed" => unconfirmed, "result" => result, "previous" => previous, "reason" => reason, "source_url" => source_url })

        json_response(
          "rejected_tags" => rejected_tags,
          "rejected_tags_note" => (rejected_tags.any? ? "These are not in the controlled vocabulary and were not applied. Use get_taxonomy for valid tags." : nil),
          "result" => result,
          "error" => (unconfirmed_error(unconfirmed) if unconfirmed.any?),
          "company_id" => company.id,
          "company_slug" => company.slug,
          "requested" => applied,
          "confirmed" => confirmed,
          "unconfirmed" => unconfirmed,
          # Kept under its original name so existing callers do not break, but it now
          # carries what was actually saved rather than what was asked for.
          "applied" => confirmed,
          "source_url" => source_url,
          "company" => company_summary(company)
        )
      rescue ActiveRecord::RecordInvalid => e
        error_response("result" => "blocked", "retryable" => false, "error" => e.message)
      rescue StandardError => e
        Rails.logger.debug("[UpdateCompanyFieldTool] transient failure for #{slug}: #{e.class}: #{e.message}")
        error_response("result" => "error", "retryable" => true, "error" => "Transient failure (#{e.class}); safe to retry: #{e.message}")
      end

      # Compares each requested value against what the reloaded record actually holds.
      # Per field, so a multi-field write that saved three of four says which one failed
      # instead of reporting a flat success or a flat failure.
      def self.confirm_saved(company, applied)
        confirmed = {}
        unconfirmed = {}

        applied.each do |field, requested|
          saved = saved_value_for(company, field)
          if values_match?(field, requested, saved)
            confirmed[field] = saved
          else
            unconfirmed[field] = { "requested" => requested, "saved" => saved }
          end
        end

        [confirmed, unconfirmed]
      end

      def self.saved_value_for(company, field)
        case field
        when "all_tags" then company.tags.map(&:name).sort.join(", ")
        else company.public_send(field)
        end
      end

      def self.values_match?(field, requested, saved)
        case field
        when "all_tags"
          tag_set(requested) == tag_set(saved)
        when "secondary_category_id"
          requested.presence.to_s == saved.presence.to_s
        else
          requested.to_s.strip == saved.to_s.strip
        end
      end

      def self.tag_set(value)
        value.to_s.split(",").map { |tag| tag.strip.downcase }.reject(&:blank?).to_set
      end

      def self.unconfirmed_error(unconfirmed)
        "The write reported success, but #{unconfirmed.keys.to_sentence} did not save: " \
          "#{unconfirmed.map { |field, pair| "#{field} was requested as #{pair['requested'].inspect} and reads back as #{pair['saved'].inspect}" }.join('; ')}."
      end


      # Provenance for an in-place edit to a live entry, and the lock that stops the next
      # automated pass undoing it. Appended, never replaced, so a record's repair history
      # stays readable.
      def self.record_edit!(company, applied:, previous:, reason:, lock:)
        review = company.quality_review.is_a?(Hash) ? company.quality_review.deep_dup : {}
        review["field_edits"] = Array(review["field_edits"]) + [{
          "at" => Time.current.utc.iso8601,
          "via" => "update_company_field",
          "reason" => reason.to_s.strip.presence,
          "changes" => applied.keys.index_with { |field| { "from" => previous[field], "to" => applied[field] } }
        }]

        if applied.key?("description")
          locked = lock.nil? ? true : ActiveModel::Type::Boolean.new.cast(lock)
          review["description_locked"] = locked
          review["description_locked_at"] = locked ? Time.current.utc.iso8601 : nil
          review["description_locked_reason"] = locked ? reason.to_s.strip.presence : nil
        end

        company.quality_review = review
      end

      def self.plausible_year?(value)
        value.to_s.strip.match?(/\A(?:19|20)\d{2}\z/) && (1970..Date.current.year).cover?(value.to_s.strip.to_i)
      end

      def self.valid_http_url?(value)
        uri = URI.parse(value.to_s.strip)
        uri.is_a?(URI::HTTP) && uri.host.present?
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
