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
    return existing if existing

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
      "blocking" => matches.any?,
      "checked_at" => Time.current.utc.iso8601
    }
  end
end
