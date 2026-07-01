class CompanyCandidateRowProcessorService
  SOURCE = CompanyCandidateImportService::SOURCE
  DUPLICATE_MERGE_FIELDS = CompanyCandidateImportService::DUPLICATE_MERGE_FIELDS

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(candidate:, index:, admin_user:, pipeline_run_id: nil, source: SOURCE, proposal_type: "atlas_candidate", source_label: "LegalTechAtlas CSV", skip_auto_draft: false)
    @candidate = candidate
    @index = index
    @admin_user = admin_user
    @pipeline_run_id = pipeline_run_id
    @source = source
    @proposal_type = proposal_type
    @source_label = source_label
    @skip_auto_draft = ActiveModel::Type::Boolean.new.cast(skip_auto_draft)
  end

  def call
    consolidate_visible_domain_duplicates!
    proposal = upsert_proposal
    return result_payload(proposal, "already_published", "Company is already published.") if proposal.status == "published" || proposal.company&.visible?
    return resolve_duplicate_candidate(proposal) if proposal.duplicate_blocking?

    CompanyProposalEnrichmentService.call(proposal: proposal, admin_user: admin_user) if enrichment_needed?(proposal) && !skip_auto_draft?
    proposal.reload

    return result_payload(proposal, "queued_for_review", "Discovery candidate queued for human review.") if skip_auto_draft?

    quality = CompanyProposalQualityService.call(proposal)
    return result_payload(proposal, "needs_review", Array(quality["blockers"]).first) unless auto_draft_ready?(proposal, quality)
    return result_payload(proposal, "already_drafted", "Proposal already has a company draft.") if proposal.company_id.present?

    company = create_hidden_draft!(proposal)
    result_payload(proposal.reload, "auto_drafted", "Invisible company draft created.", company)
  rescue StandardError => e
    result_payload(defined?(proposal) ? proposal : nil, "errored", e.message).merge(
      "error_class" => e.class.name
    )
  end

  private

  attr_reader :candidate, :index, :admin_user, :pipeline_run_id, :source, :proposal_type, :source_label, :skip_auto_draft

  def skip_auto_draft?
    skip_auto_draft
  end

  def consolidate_visible_domain_duplicates!
    domain = candidate["canonical_domain"]
    return if domain.blank?

    visible_matches = Array(candidate["domain_matches"]).select { |match| match["visible"] != false }
    return unless visible_matches.size > 1

    CompanyDuplicateConsolidationService.call(
      domains: [domain],
      reviewer: admin_user&.email || "agent",
      notes: "Consolidate visible duplicate domain before candidate import."
    )
    candidate["domain_matches"] = fresh_domain_matches(domain)
  end

  def fresh_domain_matches(domain)
    Company.where.not(main_url: [nil, ""]).select { |company| company.visible? && (company.canonical_domain.presence || company.canonical_main_domain) == domain }.first(10).map { |company| company_payload(company) }
  end

  def upsert_proposal
    proposal = CompanyProposal.find_or_initialize_by(source: source, source_identifier: source_identifier)
    base_final = proposal.final_changes.presence || proposed_changes
    attrs = {
      status: proposal.company_id.present? ? proposal.status : "pending",
      proposal_type: proposal_type,
      admin_user: admin_user,
      source_payload: source_payload,
      proposed_changes: proposed_changes,
      final_changes: base_final,
      duplicate_signals: duplicate_signals,
      reviewer_notes: reviewer_notes
    }

    # 6a: when the discovery search already classified the candidate and cited a
    # founding year, pre-fill the taxonomy and citation at creation time so the
    # proposal arrives classified — no separate enrich round-trip and no
    # "low-confidence taxonomy" hold for confident items.
    if prefill_discovery_taxonomy?(proposal)
      tax = discovery_taxonomy_prefill
      attrs[:final_changes] = base_final.merge(tax["final_changes"]) if tax["final_changes"].present?
      attrs[:agent_details] = (proposal.agent_details || {}).merge(tax["agent_details"]) if tax["agent_details"].present?
    end

    proposal.assign_attributes(attrs)
    proposal.save!
    proposal
  end

  def prefill_discovery_taxonomy?(proposal)
    proposal_type == "discovery_candidate" &&
      proposal.company_id.blank? &&
      proposal.agent_details["taxonomy_suggestion"].blank? &&
      candidate["category_name"].present?
  end

  def discovery_taxonomy_prefill
    category = Category.find_by(name: candidate["category_name"])
    business_models = Array(candidate["business_model_names"]).filter_map { |name| BusinessModel.find_by(name: name) }.uniq
    target_clients = Array(candidate["target_client_names"]).filter_map { |name| TargetClient.find_by(name: name) }.uniq

    final_changes = {
      "category_id" => category&.id,
      "business_model_id" => business_models.first&.id,
      "business_model_ids" => business_models.map(&:id).presence,
      "target_client_id" => target_clients.first&.id,
      "target_client_ids" => target_clients.map(&:id).presence
    }.compact

    suggestion = {
      "category" => { "id" => category&.id, "name" => category&.name, "accepted" => category.present? },
      "revenue_models" => { "ids" => business_models.map(&:id), "names" => business_models.map(&:name), "accepted" => business_models.any? },
      "target_clients" => { "ids" => target_clients.map(&:id), "names" => target_clients.map(&:name), "accepted" => target_clients.any? },
      "mode" => "discovery_search",
      "accepted" => category.present? && business_models.any? && target_clients.any?
    }

    agent_details = { "taxonomy_suggestion" => suggestion }
    agent_details["founded_date_source"] = discovery_founded_source if discovery_founded_source

    { "final_changes" => final_changes, "agent_details" => agent_details }
  end

  def discovery_founded_source
    url = candidate["founded_year_source"].to_s.strip
    return nil if url.blank? || proposed_changes["founded_date"].blank?

    { "source_url" => url, "mode" => "discovery_search_cited" }
  end

  def source_payload
    payload = candidate.merge("source_row_index" => index)
    payload["pipeline_run_id"] = pipeline_run_id if pipeline_run_id.present?
    payload
  end

  def create_hidden_draft!(proposal)
    changes = proposal.final_changes.slice(*CompanyProposal::EDITABLE_COMPANY_FIELDS)
    company = Company.new(changes.merge(
      "category_id" => changes["category_id"].presence,
      "secondary_category_id" => changes["secondary_category_id"].presence,
      "business_model_id" => changes["business_model_id"].presence,
      "target_client_id" => changes["target_client_id"].presence
    ))
    company.visible = false
    company.quality_status = "needs_review"
    company.verification_verdict = "automated_import_draft"
    company.enriched_at = Time.current
    company.quality_reviewed_at = Time.current
    company.canonical_domain = company.canonical_main_domain
    company.fingerprint = company.calculated_fingerprint
    company.skip_geocoding = true
    company.save!

    revenue_model_ids = Array(proposal.final_changes["business_model_ids"]).map(&:presence).compact
    if revenue_model_ids.empty? && changes["business_model_id"].present?
      revenue_model_ids = [changes["business_model_id"]]
    end
    company.business_model_ids = revenue_model_ids if revenue_model_ids.any?

    target_client_ids = Array(proposal.final_changes["target_client_ids"]).map(&:presence).compact
    if target_client_ids.empty? && changes["target_client_id"].present?
      target_client_ids = [changes["target_client_id"]]
    end
    company.target_client_ids = target_client_ids if target_client_ids.any?

    if proposal.final_changes["all_tags"].present?
      company.all_tags = proposal.final_changes["all_tags"]
      company.save!
    end

    proposal.update!(
      status: "approved_to_draft",
      company: company,
      admin_user: admin_user,
      reviewed_at: Time.current,
      approved_at: Time.current,
      reviewer_notes: [proposal.reviewer_notes, "Auto-created invisible company draft from high-confidence import data."].compact_blank.join("\n")
    )

    company
  end

  def resolve_duplicate_candidate(proposal)
    match = duplicate_company_match(proposal)
    merged_fields = match ? fill_blank_company_fields!(match, proposal) : []
    reason = if match
      "Duplicate matched existing company; filled blank fields: #{merged_fields.to_sentence.presence || 'none'}."
    else
      "Duplicate matched multiple existing companies; no new company created."
    end

    proposal.update!(
      status: "rejected",
      company: match,
      rejected_at: Time.current,
      reviewed_at: Time.current,
      admin_user: admin_user,
      rejection_reason: reason,
      reviewer_notes: [proposal.reviewer_notes, reason].compact_blank.join("\n")
    )

    result_payload(proposal.reload, match ? "duplicate_merged" : "duplicate_rejected", reason, match).merge(
      "merged_fields" => merged_fields
    )
  end

  def duplicate_company_match(proposal)
    matches = Array(proposal.duplicate_signals["domain_matches"]) + Array(proposal.duplicate_signals["name_matches"])
    ids = matches.filter_map { |match| match["id"] }.uniq
    return unless ids.one?

    Company.find_by(id: ids.first)
  end

  def fill_blank_company_fields!(company, proposal)
    changes = proposal.final_changes.slice(*DUPLICATE_MERGE_FIELDS)
    updates = changes.each_with_object({}) do |(field, value), attrs|
      next if value.blank?
      next unless company.respond_to?(field)
      next if company.public_send(field).present?

      attrs[field] = value
    end

    return [] if updates.empty?

    company.assign_attributes(updates)
    company.canonical_domain = company.canonical_main_domain if company.respond_to?(:canonical_domain) && company.canonical_domain.blank?
    company.fingerprint = company.calculated_fingerprint if company.respond_to?(:fingerprint) && company.fingerprint.blank?
    company.enriched_at ||= Time.current if company.respond_to?(:enriched_at)
    company.skip_geocoding = true
    company.save!(validate: false)
    updates.keys
  end

  def auto_draft_ready?(proposal, quality)
    quality["publish_ready"] &&
      proposal.agent_details.dig("taxonomy_suggestion", "accepted") &&
      !proposal.duplicate_blocking?
  end

  def enrichment_needed?(proposal)
    changes = proposal.editable_changes
    details = proposal.agent_details || {}

    changes["description"].blank? ||
      proposal.missing_taxonomy_field_keys(changes).any? ||
      details["taxonomy_suggestion"].blank? ||
      details["description_critic"].blank?
  end

  def proposed_changes
    {
      "name" => candidate["name"],
      "main_url" => candidate["website"],
      "location" => location_value(candidate),
      "founded_date" => founded_year(candidate["founded_date"]),
      "status" => company_status(candidate["operating_status"]),
      "description" => nil,
      "crunchbase_url" => candidate["crunchbase_url"],
      "linkedin_url" => candidate["linkedin_url"],
      "total_funding_amount_usd" => candidate["funding_amount_usd"],
      "funding_status" => candidate["company_type"],
      "number_of_funding_rounds" => candidate["number_of_funding_rounds"],
      "founders" => candidate["founders"],
      "source" => source_label,
      "source_url" => candidate["crunchbase_url"].presence || candidate["website"]
    }.compact
  end

  def duplicate_signals
    {
      "name_matches" => Array(candidate["name_matches"]),
      "domain_matches" => Array(candidate["domain_matches"]),
      "recommended_action" => candidate["recommended_action"]
    }
  end

  def reviewer_notes
    if proposal_type == "discovery_candidate"
      if candidate["status"] == "existing_or_possible_duplicate"
        "LLM discovery candidate requires duplicate review before any company draft is created."
      else
        "LLM discovery candidate queued for human review. No auto-publish or auto-draft in discovery pilot."
      end
    elsif candidate["status"] == "existing_or_possible_duplicate"
      "Imported candidate requires duplicate review before any company draft is created."
    else
      "Imported candidate was processed automatically. Clean rows may become invisible drafts; exceptions remain here for review."
    end
  end

  def result_payload(proposal, action, reason, company = nil)
    {
      "row_index" => index,
      "name" => candidate["name"],
      "status" => candidate["status"],
      "action" => action,
      "reason" => reason,
      "proposal_id" => proposal&.id,
      "company_id" => company&.id || proposal&.company_id,
      "canonical_domain" => candidate["canonical_domain"]
    }.compact
  end

  def source_identifier
    candidate["canonical_domain"].presence || Company.normalized_name_value(candidate["name"])
  end

  def location_value(candidate)
    LocationCountryResolver.format_for_display(candidate["location"])
  end

  def founded_year(value)
    value.to_s[/\d{4}/]
  end

  def company_status(value)
    value.to_s.downcase == "closed" ? "inactive" : "active"
  end

  def company_payload(company)
    {
      "id" => company.id,
      "name" => company.name,
      "main_url" => company.main_url,
      "canonical_domain" => company.canonical_domain.presence || company.canonical_main_domain,
      "visible" => company.visible,
      "quality_status" => company.quality_status
    }
  end
end
