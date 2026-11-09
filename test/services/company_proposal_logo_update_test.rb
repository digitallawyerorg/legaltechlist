require "test_helper"

# Proposal 11110 (CoverPin): "The logo is missing". Nothing in the proposal flow could
# set a logo, so the suggestion sat in the queue with no way to act on it.
class CompanyProposalLogoUpdateTest < ActiveSupport::TestCase
  setup do
    @admin = admin_users(:one)
    @company = companies(:one)
  end

  def suggestion(changes, status: "ready_for_review")
    CompanyProposal.create!(
      status: status, proposal_type: "user_suggestion", source: "user_suggestion",
      source_identifier: SecureRandom.uuid, source_payload: {}, company: @company,
      proposed_changes: {}, final_changes: changes, duplicate_signals: {}
    )
  end

  test "applying a logo URL replaces the stored logo so the new one is shown" do
    @company.create_company_logo!(data: "old-bytes", content_type: "image/png")

    CompanyProposalApplyUpdateService.call(proposal: suggestion({ "logo_url" => "https://cdn.example.com/coverpin.png" }), admin_user: @admin)

    @company.reload
    assert_equal "https://cdn.example.com/coverpin.png", @company.logo_url
    assert_nil @company.company_logo
    assert_equal "https://cdn.example.com/coverpin.png", @company.logo
  end

  test "a suggestion that does not touch the logo leaves the stored logo alone" do
    @company.create_company_logo!(data: "old-bytes", content_type: "image/png")

    CompanyProposalApplyUpdateService.call(proposal: suggestion({ "location" => "Malta" }), admin_user: @admin)

    assert @company.reload.company_logo.present?
  end

  test "a published suggestion cannot be applied a second time" do
    proposal = suggestion({ "location" => "Malta" }, status: "published")

    error = assert_raises(ArgumentError) { CompanyProposalApplyUpdateService.call(proposal: proposal, admin_user: @admin) }
    assert_match(/already published/, error.message)
  end

  test "a rejected suggestion cannot be applied" do
    proposal = suggestion({ "location" => "Malta" }, status: "rejected")

    assert_raises(ArgumentError) { CompanyProposalApplyUpdateService.call(proposal: proposal, admin_user: @admin) }
  end
end
