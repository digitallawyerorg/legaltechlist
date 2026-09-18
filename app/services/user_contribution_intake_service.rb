class UserContributionIntakeService
  SOURCE = "user_contribution"

  def self.call(form:, request_ip: nil)
    new(form: form, request_ip: request_ip).call
  end

  def initialize(form:, request_ip: nil)
    @form = form
    @request_ip = request_ip
  end

  def call
    raise ActiveRecord::RecordInvalid, form unless form.valid?

    # One submission, one proposal. Twins arrived 1, 21 and 49 seconds apart because
    # identity lived in an expiring cache key rather than on the record, so a double
    # submit — or a retried request — produced two rows for the same company.
    existing = CompanyProposal.find_by(source: SOURCE, source_identifier: submission_identity)
    if existing
      # A resubmission of a record a reviewer explicitly asked the contributor to fix is
      # the one case where the second payload is the point. Every other repeat is still a
      # duplicate submit and is still discarded.
      return reopen_returned!(existing) if awaiting_contributor?(existing)

      return existing
    end

    proposal = CompanyProposal.create!(
      status: "pending",
      proposal_type: "user_contribution",
      source: SOURCE,
      source_identifier: submission_identity,
      source_payload: form.source_payload,
      proposed_changes: form.proposed_changes,
      final_changes: form.proposed_changes,
      duplicate_signals: duplicate_signals,
      submitter_email: form.contact_email.to_s.strip,
      submitter_name: form.contact_name.to_s.strip,
      agent_details: { "intake" => { "request_ip" => request_ip, "channel" => "public_contribute_form" } }
    )

    SlackNotifier.user_contribution_submitted(proposal)
    UserContributionProcessingJob.perform_later(proposal.id)
    proposal
  end

  private

  attr_reader :form, :request_ip

  def awaiting_contributor?(proposal)
    proposal.status == CompanyProposalReturnService::RETURNED_PROPOSAL_STATUS &&
      proposal.agent_details.dig("current_contributor_request", "state") == CompanyProposalReturnService::AWAITING_STATE
  end

  # The contributor answered: take the new payload, put the record back in front of a
  # reviewer, and close the outstanding request while keeping every round of history.
  def reopen_returned!(proposal)
    details = proposal.agent_details.deep_dup
    answered = details.delete("current_contributor_request")
    details["contributor_resubmissions"] = Array(details["contributor_resubmissions"]) + [{
      "resubmitted_at" => Time.current.utc.iso8601,
      "request_ip" => request_ip,
      "answered_request_at" => answered&.dig("requested_at"),
      "round" => Array(details["contributor_requests"]).size
    }.compact]

    proposal.update!(
      source_payload: form.source_payload,
      proposed_changes: form.proposed_changes,
      final_changes: form.proposed_changes,
      # Back on the Review Tab: the request is gone, so it is no longer filtered out of
      # the reviewer's default view.
      status: "ready_for_review",
      agent_details: details
      # reviewed_at is deliberately left as it was. It records that a human looked at
      # this record, which is still true, and while it is set enrichment stays locked
      # (CompanyProposalEnrichmentService#locked_reason) — the safer default for a record
      # a reviewer has already had opinions about. A reviewer can still force enrichment.
    )

    # A resubmitted payload can name a different company than the one that was checked
    # the first time round, so the duplicate state is recomputed against the index as it
    # is now rather than left as the snapshot taken at first intake. Approval re-resolves
    # it live as well, so neither the queue nor the gate is reading a stale answer.
    proposal.refresh_duplicate_signals!

    SlackNotifier.user_contribution_submitted(proposal)
    # Enqueued exactly as a first submission is. The processor stands down on a record a
    # human has already handled (it only processes status "pending"), which is the right
    # outcome here: a record a reviewer has already had opinions about must not be
    # auto-published by triage, and the duplicate gate still runs at approval.
    UserContributionProcessingJob.perform_later(proposal.id)
    proposal
  end

  # Stable for the same company from the same submitter, so a repeat lands on the row
  # that already exists instead of creating a second one.
  def submission_identity
    @submission_identity ||= begin
      key = [
        Company.canonical_domain_for(form.main_url) || Company.normalized_name_value(form.name),
        form.contact_email.to_s.strip.downcase
      ].compact_blank.join("|")
      key.presence ? Digest::SHA256.hexdigest(key) : SecureRandom.uuid
    end
  end

  def duplicate_signals
    domain = Company.canonical_domain_for(form.main_url)
    normalized_name = Company.normalized_name_value(form.name)

    {
      "name_matches" => name_matches(normalized_name),
      "domain_matches" => domain_matches(domain),
      "recommended_action" => domain.present? ? "Review duplicate domain before approval." : nil
    }.compact
  end

  def name_matches(normalized_name)
    return [] if normalized_name.blank?

    Company.where.not(name: [nil, ""]).select { |company| Company.normalized_name_value(company.name) == normalized_name }.first(5).map { |company| company_match_payload(company) }
  end

  def domain_matches(domain)
    return [] if domain.blank?

    Company.where.not(main_url: [nil, ""]).select { |company| company.canonical_main_domain == domain }.first(5).map { |company| company_match_payload(company) }
  end

  def company_match_payload(company)
    {
      "id" => company.id,
      "name" => company.name,
      "main_url" => company.main_url,
      "canonical_domain" => company.canonical_main_domain,
      "visible" => company.visible?
    }
  end
end
