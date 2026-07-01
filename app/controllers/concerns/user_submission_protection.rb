module UserSubmissionProtection
  extend ActiveSupport::Concern

  HONEYPOT_PARAM = :website_url
  MIN_SUGGESTION_MESSAGE_LENGTH = 15
  MIN_CONTRIBUTION_DESCRIPTION_LENGTH = 30

  included do
    before_action :protect_user_submission, only: [:create, :suggest_update]
  end

  private

  def protect_user_submission
    return silently_reject_bot if params[HONEYPOT_PARAM].present?
    return silently_reject_duplicate if duplicate_submission?
    return reject_rate_limited unless rate_limit_allowed?

    nil
  end

  def silently_reject_bot
    Rails.logger.debug("[UserSubmissionProtection] Honeypot triggered path=#{request.path} ip=#{request.remote_ip}")
    redirect_to bot_redirect_path, notice: submission_thank_you_notice
  end

  def silently_reject_duplicate
    Rails.logger.debug("[UserSubmissionProtection] Duplicate submission path=#{request.path} ip=#{request.remote_ip} email=#{submission_email}")
    redirect_to bot_redirect_path, notice: submission_thank_you_notice
  end

  def reject_rate_limited
    Rails.logger.debug("[UserSubmissionProtection] Rate limit exceeded path=#{request.path} ip=#{request.remote_ip} action=#{submission_rate_limit_action} email=#{submission_email}")
    flash.now[:alert] = "Too many submissions from your network. Please try again later."
    render_submission_form_unprocessable(status: :too_many_requests)
  end

  def rate_limit_allowed?
    limiter = SubmissionRateLimiter.new(ip: request.remote_ip, action: submission_rate_limit_action, email: submission_email)
    return false unless limiter.allow?

    limiter.record!
    true
  end

  def duplicate_submission?
    fingerprint = submission_fingerprint
    return false if fingerprint.blank?

    SubmissionDuplicateDetector.duplicate?(fingerprint: fingerprint)
  end

  def record_submission_fingerprint!
    fingerprint = submission_fingerprint
    return if fingerprint.blank?

    SubmissionDuplicateDetector.record!(fingerprint: fingerprint)
  end

  def submission_fingerprint
    case submission_rate_limit_action
    when "company_contribution"
      contribution = params[:company_contribution]
      return if contribution.blank?

      [
        contribution[:contact_email],
        contribution[:main_url],
        contribution[:name],
        contribution[:description]
      ].map { |value| value.to_s.strip.downcase }.join("|")
    when "company_suggestion"
      [
        params[:submitter_email],
        params[:slug],
        params[:issue_type],
        params[:message]
      ].map { |value| value.to_s.strip.downcase }.join("|")
    end
  end

  def submission_email
    case submission_rate_limit_action
    when "company_contribution"
      params.dig(:company_contribution, :contact_email)
    when "company_suggestion"
      params[:submitter_email]
    end
  end

  def submission_rate_limit_action
    action_name == "create" ? "company_contribution" : "company_suggestion"
  end

  def bot_redirect_path
    action_name == "create" ? companies_path : company_path(params[:slug])
  end

  def submission_thank_you_notice
    "Thank you. Your submission has been received for review."
  end

  def render_submission_form_unprocessable(status: :unprocessable_entity)
    if action_name == "create"
      @contribution_form ||= begin
        CompanyContributionForm.from_params(params)
      rescue ActionController::ParameterMissing
        CompanyContributionForm.new
      end
      render :new, status: status
    else
      redirect_to company_path(params[:slug]), alert: flash.now[:alert]
    end
  end
end
