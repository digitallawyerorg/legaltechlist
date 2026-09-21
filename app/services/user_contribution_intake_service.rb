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
    # is now rather than left as the snapshot taken at first intake.
    proposal.refresh_duplicate_signals!

    # The gate runs on this path too. It is the one ingestion path that reopens a record
    # *past* the processor: the processor routes blocking duplicates (it calls the gate
    # before anything else), but it only touches status "pending", so a record reopened
    # to "ready_for_review" here is skipped by it. Without this call a resubmission that
    # now matches a published record would land in the normal review queue carrying no
    # routing entry, no reviewer note and no named canonical record — the exact hole the
    # gate exists to close, reopened from the other side. Duplicate detection is
    # mandatory on every path, so it is asked here rather than left to approval.
    #
    # It routes, it does not refuse: refusing would raise into the contribute form and
    # throw away the contributor's answer. Routing keeps the payload, keeps the record
    # open, and puts it in front of a human with the canonical record named on it.
    decision = DuplicateGate.check(proposal, refresh: false)
    DuplicateGate.route!(decision) if decision.blocking?

    SlackNotifier.user_contribution_submitted(proposal)
    # Enqueued exactly as a first submission is. The processor stands down on a record a
    # human has already handled (it only processes status "pending"), which is the right
    # outcome here: a record a reviewer has already had opinions about must not be
    # auto-published by triage.
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

  # The signals the row is created with, from the same matcher every later reader uses.
  #
  # This used to compare exact normalized names and exact canonical domains, and to set
  # recommended_action to "Review duplicate domain before approval." whenever the
  # submission had a URL at all — advice against empty match arrays, which is how the
  # stored signals came to be read as noise. It now says nothing unless something matched,
  # and says what matched.
  def duplicate_signals
    matches = CompanyIdentityMatcher.matches_for(
      name: form.name,
      domains: [Company.canonical_domain_for(form.main_url)],
      profiles: CompanyIdentityMatcher.profile_keys("linkedin_url" => form.linkedin_url, "crunchbase_url" => form.crunchbase_url)
    )

    {
      "name_matches" => CompanyIdentityMatcher.name_matches(matches),
      "domain_matches" => CompanyIdentityMatcher.domain_matches(matches),
      # The same grade the gate applies, rather than "something matched". This blob is
      # the snapshot the triage and verifier agents read, and a second definition of
      # "blocking" living here would stamp a pair as a duplicate on the one path where
      # the gate itself had already declined to.
      "blocking" => matches.any? { |match| match["surfacing"] == CompanyIdentityMatcher::SURFACING_BLOCKING },
      "advisory" => matches.any? { |match| match["surfacing"] == CompanyIdentityMatcher::SURFACING_ADVISORY },
      "checked_at" => Time.current.utc.iso8601
    }
  end
end
