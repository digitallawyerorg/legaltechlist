class UserSuggestionIntakeService
  SOURCE = "user_suggestion"
  MIN_MESSAGE_LENGTH = UserSubmissionProtection::MIN_SUGGESTION_MESSAGE_LENGTH

  def self.call(company:, suggestion:, request_ip: nil)
    new(company: company, suggestion: suggestion, request_ip: request_ip).call
  end

  def initialize(company:, suggestion:, request_ip: nil)
    @company = company
    @suggestion = suggestion.symbolize_keys
    @request_ip = request_ip
  end

  def call
    validate!

    proposal = CompanyProposal.create!(
      status: "pending",
      proposal_type: "user_suggestion",
      source: SOURCE,
      source_identifier: SecureRandom.uuid,
      company: company,
      source_payload: source_payload,
      proposed_changes: company_snapshot,
      final_changes: company_snapshot,
      duplicate_signals: {},
      submitter_email: suggestion[:submitter_email].to_s.strip,
      issue_type: suggestion[:issue_type].to_s.strip,
      user_message: suggestion[:message].to_s.strip,
      agent_details: { "intake" => { "request_ip" => request_ip, "channel" => "suggest_update_modal" } }
    )

    SlackNotifier.user_suggestion_submitted(proposal)
    UserContributionProcessingJob.perform_later(proposal.id)
    proposal
  end

  private

  attr_reader :company, :suggestion, :request_ip

  def validate!
    raise ArgumentError, "Issue type is required" if suggestion[:issue_type].blank?
    raise ArgumentError, "Issue type is not supported" unless UserSuggestionIssueTypes.valid?(suggestion[:issue_type])
    raise ArgumentError, "Message is required" if suggestion[:message].blank?
    raise ArgumentError, "Message is too short" if suggestion[:message].to_s.strip.length < MIN_MESSAGE_LENGTH
    raise ArgumentError, "Submitter email is required" if suggestion[:submitter_email].blank?
  end

  def source_payload
    {
      "company_id" => company.id,
      "company_name" => company.name,
      "issue_type" => suggestion[:issue_type],
      "message" => suggestion[:message],
      "source_url" => suggestion[:source_url].presence,
      "submitter_email" => suggestion[:submitter_email],
      "submission_channel" => "suggest_update_modal"
    }
  end

  def company_snapshot
    {
      "name" => company.name,
      "main_url" => company.main_url,
      "location" => company.location,
      "founded_date" => company.founded_date,
      "status" => company.status,
      "description" => company.description,
      "category_id" => company.category_id,
      "secondary_category_id" => company.secondary_category_id,
      "business_model_id" => company.business_model_id,
      "business_model_ids" => company.business_models.map(&:id).presence || Array(company.business_model_id).compact,
      "target_client_id" => company.target_client_id,
      "target_client_ids" => company.target_clients.map(&:id).presence || Array(company.target_client_id).compact,
      "all_tags" => company.all_tags,
      "crunchbase_url" => company.crunchbase_url,
      "linkedin_url" => company.linkedin_url
    }.compact
  end
end
