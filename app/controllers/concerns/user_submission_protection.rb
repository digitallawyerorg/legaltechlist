module UserSubmissionProtection
  extend ActiveSupport::Concern

  HONEYPOT_PARAM = :website_url

  included do
    before_action :protect_user_submission, only: [:create, :suggest_update]
  end

  private

  def protect_user_submission
    return silently_reject_bot if params[HONEYPOT_PARAM].present?

    unless rate_limit_allowed?
      flash.now[:alert] = "Too many submissions from your network. Please try again later."
      render_submission_form_unprocessable(status: :too_many_requests)
      return
    end
  end

  def silently_reject_bot
    Rails.logger.debug("[UserSubmissionProtection] Honeypot triggered path=#{request.path}")
    redirect_to bot_redirect_path, notice: submission_thank_you_notice
  end

  def rate_limit_allowed?
    limiter = SubmissionRateLimiter.new(ip: request.remote_ip, action: submission_rate_limit_action)
    return false unless limiter.allow?

    limiter.record!
    true
  end

  def submission_rate_limit_action
    action_name == "create" ? "company_contribution" : "company_suggestion"
  end

  def bot_redirect_path
    action_name == "create" ? companies_path : company_path(@company)
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
      redirect_to @company, alert: flash.now[:alert]
    end
  end
end
