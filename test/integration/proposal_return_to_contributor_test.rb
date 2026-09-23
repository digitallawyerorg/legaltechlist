require "test_helper"

# The reviewer's side of returning a proposal: it happens on the Review Tab, from the
# proposal itself, and it neither creates a company draft nor leaves the record sitting
# in the default queue as though it were still someone's review task.
class ProposalReturnToContributorTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in admin_users(:one)
    @proposal = contribution_proposal
  end

  def contribution_proposal(status: "ready_for_review")
    changes = {
      "name" => "Pactolane", "main_url" => "https://www.pactolane.example",
      "description" => "Pactolane builds contract lifecycle management software for legal teams.",
      "location" => "Lyon, France"
    }
    CompanyProposal.create!(
      status: status, proposal_type: "user_contribution", source: "user_contribution",
      source_identifier: SecureRandom.uuid, source_payload: {}, submitter_email: "founder@pactolane.example",
      proposed_changes: changes, final_changes: changes, duplicate_signals: {}
    )
  end

  test "the proposal page offers a return to contributor form that requires instructions" do
    get custom_admin_company_proposal_path(@proposal)

    assert_response :success
    assert_select "form[action=?][method=?]", return_to_contributor_custom_admin_company_proposal_path(@proposal), "post"
    assert_select "textarea[name='contributor_instructions'][required]"
    assert_select "input[type=submit][value='Return to contributor']"
    # No submitter-facing notification exists anywhere in the app, so nothing on the page
    # may suggest the contributor was told.
    refute_match(/email (was |has been )?sent|we(’|')?ll email|notified by email/i, response.body)
  end

  test "returning a proposal parks it, creates no company, and lands the reviewer back in their queue" do
    assert_no_difference "Company.count" do
      post return_to_contributor_custom_admin_company_proposal_path(@proposal), params: {
        contributor_instructions: "The website returns a 404 — please supply a current URL.",
        contributor_fields: %w[main_url],
        queue: { status: "user_contributions" }
      }
    end

    assert_redirected_to custom_admin_company_proposals_path(status: "user_contributions")
    assert_match(/parked for its contributor/, flash[:notice])
    assert_match(/No company draft was created/, flash[:notice])
    # A flash is rendered by whatever page this browser loads next, public pages
    # included, so the contributor's address is named on the proposal and nowhere else
    # (PublicContributeFormPrivacyTest).
    refute_includes flash[:notice], "founder@pactolane.example"

    @proposal.reload
    assert_equal "needs_revision", @proposal.status
    assert_nil @proposal.company_id
    assert_equal "The website returns a 404 — please supply a current URL.",
                 @proposal.agent_details.dig("current_contributor_request", "instructions")
  end

  test "a proposal waiting on its contributor leaves the default queue and has its own chip" do
    CompanyProposalReturnService.call(proposal: @proposal, admin_user: admin_users(:one), instructions: "Please supply a current URL.")

    get custom_admin_company_proposals_path
    assert_response :success
    refute_includes response.body, "/admin/proposals/#{@proposal.id}", "it is nobody's review task while the next move is the contributor's"
    assert_select "a", text: /Awaiting contributor 1/

    get custom_admin_company_proposals_path(status: "awaiting_contributor")
    assert_response :success
    assert_includes response.body, "/admin/proposals/#{@proposal.id}"
  end

  test "the outstanding request is shown on the proposal itself" do
    CompanyProposalReturnService.call(
      proposal: @proposal, admin_user: admin_users(:one),
      instructions: "The description does not say what the product does.", fields: %w[description]
    )

    get custom_admin_company_proposal_path(@proposal)

    assert_response :success
    assert_select ".alert-warning", text: /Waiting on the contributor/
    assert_includes response.body, "The description does not say what the product does."
    assert_includes response.body, "founder@pactolane.example"
  end

  test "blank instructions are refused and nothing is written" do
    post return_to_contributor_custom_admin_company_proposal_path(@proposal), params: { contributor_instructions: "" }

    assert_redirected_to custom_admin_company_proposal_path(@proposal)
    assert_match(/was not returned to its contributor/, flash[:alert])
    @proposal.reload
    assert_equal "ready_for_review", @proposal.status
    assert_nil @proposal.agent_details["current_contributor_request"]
  end

  test "a proposal that has left the review queue cannot be returned" do
    rejected = contribution_proposal(status: "rejected")

    post return_to_contributor_custom_admin_company_proposal_path(rejected), params: { contributor_instructions: "Please supply a current URL." }

    assert_redirected_to custom_admin_company_proposal_path(rejected)
    assert_match(/left the review queue/, flash[:alert])
    assert_equal "rejected", rejected.reload.status
  end
end
