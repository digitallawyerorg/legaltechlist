class CompanyReviewMarkService
  DECISIONS = %w[verified needs_work reject].freeze

  def self.call(company:, decision:, admin_user: nil)
    new(company: company, decision: decision, admin_user: admin_user).call
  end

  def initialize(company:, decision:, admin_user: nil)
    @company = company
    @decision = decision.to_s
    @admin_user = admin_user
  end

  def call
    raise ArgumentError, "Unknown review decision: #{decision}" unless DECISIONS.include?(decision)

    case decision
    when "verified"
      company.update!(
        quality_status: "verified",
        verification_verdict: "human_confirmed",
        human_reviewed_at: Time.current,
        quality_reviewed_at: Time.current,
        verified_at: company.verified_at || Time.current
      )
    when "needs_work"
      company.update!(
        quality_status: "needs_review",
        verification_verdict: "needs_human_review",
        human_reviewed_at: Time.current,
        quality_reviewed_at: Time.current
      )
    when "reject"
      company.update!(
        quality_status: "rejected",
        verification_verdict: "human_rejected",
        visible: false,
        human_reviewed_at: Time.current,
        quality_reviewed_at: Time.current
      )
    end

    company
  end

  private

  attr_reader :company, :decision, :admin_user
end
