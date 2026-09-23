require "test_helper"

# Nothing a reviewer does to a proposal may put the submitter's address, or the text of
# the request made of them, onto a page an unauthenticated visitor renders.
#
# The suggest-a-company form renders the flash hash, and a flash is session state that
# is delivered to whatever page the browser loads next — so an admin message that names
# a contributor was printed on the public form, twice, once by an explicit notice/alert
# pair and once by the loop over the same hash.
class PublicContributeFormPrivacyTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  CONTRIBUTOR_EMAIL = "founder@example.com".freeze
  INSTRUCTIONS = "The website returns a 404 — please supply a current URL.".freeze

  setup do
    changes = {
      "name" => "Nomos", "main_url" => "https://www.nomos.example",
      "description" => "Nomos builds contract tooling for in-house legal teams.",
      "location" => "Berlin, Germany"
    }
    @proposal = CompanyProposal.create!(
      status: "ready_for_review", proposal_type: "user_contribution", source: "user_contribution",
      source_identifier: SecureRandom.uuid, source_payload: {}, submitter_email: CONTRIBUTOR_EMAIL,
      proposed_changes: changes, final_changes: changes, duplicate_signals: {}
    )
  end

  def assert_no_contributor_disclosure(body)
    refute_includes body, CONTRIBUTOR_EMAIL, "the submitter's address reached an unauthenticated response"
    refute_includes body, INSTRUCTIONS, "the contributor request text reached an unauthenticated response"
    refute_match(/current_contributor_request|awaiting_contributor|needs_revision/, body)
  end

  test "a returned proposal in the index discloses nothing on the public suggest-a-company form" do
    CompanyProposalReturnService.call(proposal: @proposal, admin_user: admin_users(:one), instructions: INSTRUCTIONS)

    get new_company_path

    assert_response :success
    assert_no_contributor_disclosure(response.body)
  end

  test "the notice from returning a proposal carries no contributor address onto the public form" do
    sign_in admin_users(:one)
    post return_to_contributor_custom_admin_company_proposal_path(@proposal),
         params: { contributor_instructions: INSTRUCTIONS, contributor_fields: %w[main_url] }
    sign_out admin_users(:one)

    get new_company_path

    assert_response :success
    assert_no_contributor_disclosure(response.body)
    # The same flash, printed once. Two render sites is how one leak became two.
    assert_select ".company-suggest-flash", 1
  end

  test "a refused return carries no contributor address onto the public form" do
    sign_in admin_users(:one)
    @proposal.stub(:update!, true) do
      CompanyProposal.stub(:find, @proposal) do
        post return_to_contributor_custom_admin_company_proposal_path(@proposal),
             params: { contributor_instructions: INSTRUCTIONS }
      end
    end
    assert_match(/was not returned to its contributor/, flash[:alert])
    refute_includes flash[:alert], CONTRIBUTOR_EMAIL
    refute_includes flash[:alert], INSTRUCTIONS
    sign_out admin_users(:one)

    get new_company_path

    assert_response :success
    assert_no_contributor_disclosure(response.body)
  end

  test "the public company page discloses nothing from a returned proposal either" do
    sign_in admin_users(:one)
    post return_to_contributor_custom_admin_company_proposal_path(@proposal),
         params: { contributor_instructions: INSTRUCTIONS }
    sign_out admin_users(:one)

    get company_path(companies(:one))

    assert_response :success
    assert_no_contributor_disclosure(response.body)
  end

  test "the reviewer is still told the proposal was parked, and for whom, without the address" do
    sign_in admin_users(:one)
    post return_to_contributor_custom_admin_company_proposal_path(@proposal),
         params: { contributor_instructions: INSTRUCTIONS }

    assert_match(/parked for its contributor/, flash[:notice])
    refute_includes flash[:notice], CONTRIBUTOR_EMAIL
    # The address is still on the record, where only a signed-in reviewer reads it.
    assert_equal CONTRIBUTOR_EMAIL, @proposal.reload.agent_details.dig("current_contributor_request", "contributor_email")
  end
end
