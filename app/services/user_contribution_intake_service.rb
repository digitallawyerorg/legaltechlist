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

    proposal = CompanyProposal.create!(
      status: "pending",
      proposal_type: "user_contribution",
      source: SOURCE,
      source_identifier: SecureRandom.uuid,
      source_payload: form.source_payload,
      proposed_changes: form.proposed_changes,
      final_changes: form.proposed_changes,
      duplicate_signals: duplicate_signals,
      submitter_email: form.contact_email.to_s.strip,
      submitter_name: form.contact_name.to_s.strip.presence,
      agent_details: { "intake" => { "request_ip" => request_ip, "channel" => "public_contribute_form" } }
    )

    SlackNotifier.user_contribution_submitted(proposal)
    UserContributionProcessingJob.perform_later(proposal.id)
    proposal
  end

  private

  attr_reader :form, :request_ip

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
