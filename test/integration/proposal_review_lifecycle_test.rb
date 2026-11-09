require "test_helper"

# Reviewer feedback (Nov 2026): rejected proposals still showed Reject / Approve Draft /
# Publish, a review that changed nothing left no trace, and a logo could not be set
# through a proposal at all.
class ProposalReviewLifecycleTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = admin_users(:one)
    sign_in @admin
    @proposal = CompanyProposal.create!(
      status: "ready_for_review", proposal_type: "discovery_candidate", source: "llm_discovery",
      source_identifier: SecureRandom.uuid, source_payload: {}, duplicate_signals: {},
      proposed_changes: { "name" => "Zephyr" }, final_changes: { "name" => "Zephyr" }
    )
  end

  # ---- rejected proposals are read-only ----------------------------------

  test "a rejected proposal shows no decision buttons, only reopen" do
    @proposal.update!(status: "rejected", rejected_at: Time.current, rejection_reason: "Not legal tech.")

    get custom_admin_company_proposal_path(@proposal)

    assert_response :success
    assert_select "button", text: "Reject", count: 0
    assert_select "button", text: "Approve Draft", count: 0
    assert_select "button", text: "Publish", count: 0
    assert_select "button[data-bs-target='#proposalReturnPanel']", count: 0
    assert_select "#proposalRejectPanel", count: 0
    assert_select "input[type=submit][value='Reopen for review']", count: 1
    assert_includes response.body, "Not legal tech."
  end

  test "an open proposal still shows its decision buttons" do
    get custom_admin_company_proposal_path(@proposal)

    assert_response :success
    assert_select "button", text: "Reject", count: 1
    assert_select "input[type=submit][value='Reopen for review']", count: 0
  end

  test "a published suggestion no longer offers to apply itself again" do
    suggestion = CompanyProposal.create!(
      status: "published", proposal_type: "user_suggestion", source: "user_suggestion",
      source_identifier: SecureRandom.uuid, source_payload: {}, company: companies(:one),
      proposed_changes: {}, final_changes: { "location" => "Malta" }, duplicate_signals: {}
    )

    get custom_admin_company_proposal_path(suggestion)

    assert_response :success
    assert_select "button", text: "Apply to Company", count: 0
    assert_select "button", text: "Reject", count: 0
  end

  test "editing a rejected proposal is refused" do
    @proposal.update!(status: "rejected", rejected_at: Time.current)

    get edit_custom_admin_company_proposal_path(@proposal)
    assert_redirected_to custom_admin_company_proposal_path(@proposal)

    patch custom_admin_company_proposal_path(@proposal), params: { company_proposal: { final_changes: { name: "Changed" } } }
    assert_redirected_to custom_admin_company_proposal_path(@proposal)
    assert_equal "Zephyr", @proposal.reload.final_changes["name"]
    assert_equal "rejected", @proposal.status
  end

  test "reopening puts a rejected proposal back in the queue and keeps the old reason in the log" do
    @proposal.update!(status: "rejected", rejected_at: Time.current, rejection_reason: "Looked like a duplicate.",
                      agent_details: { "canonical_record" => { "company_id" => 1 } })

    post reopen_custom_admin_company_proposal_path(@proposal), params: { reopen_note: "The other record is a different company." }

    @proposal.reload
    assert_equal "ready_for_review", @proposal.status
    assert_nil @proposal.rejected_at
    assert_nil @proposal.rejection_reason
    assert_nil @proposal.agent_details["canonical_record"]
    assert_equal "Looked like a duplicate.", @proposal.agent_details["reopened_from"].last["rejection_reason"]
    entry = @proposal.latest_review
    assert_equal "reopened", entry["outcome"]
    assert_equal @admin.email, entry["reviewer"]
    assert_match(/different company.*Previously rejected: Looked like a duplicate\./, entry["note"])
    assert_includes CompanyProposal.pending_review, @proposal
  end

  test "only rejected proposals can be reopened" do
    post reopen_custom_admin_company_proposal_path(@proposal)

    assert_match(/Only rejected/, flash[:alert].to_s)
    assert_equal "ready_for_review", @proposal.reload.status
  end

  # ---- reviewed, no change -----------------------------------------------

  test "recording 'reviewed — no change' leaves the status alone and is shown in the queue" do
    post record_review_custom_admin_company_proposal_path(@proposal), params: { review_outcome: "no_change", review_note: "Checked the site; fine as is." }

    @proposal.reload
    assert_equal "ready_for_review", @proposal.status
    entry = @proposal.latest_review
    assert_equal "no_change", entry["outcome"]
    assert_equal @admin.email, entry["reviewer"]
    assert_equal "Checked the site; fine as is.", entry["note"]
    assert_match(/\AReviewed — no change \| #{Regexp.escape(@admin.email)} \| \d{4}-\d{2}-\d{2}\z/, CompanyProposalReviewLog.label(entry))

    get custom_admin_company_proposals_path(status: "pending_review")
    assert_includes response.body, "Reviewed — no change | #{@admin.email}"
  end

  test "'needs more work' requires a note and moves the proposal to needs revision" do
    post record_review_custom_admin_company_proposal_path(@proposal), params: { review_outcome: "needs_more_work" }
    assert_match(/Say what still needs doing/, flash[:alert].to_s)
    assert_empty @proposal.reload.review_log

    post record_review_custom_admin_company_proposal_path(@proposal), params: { review_outcome: "needs_more_work", review_note: "Founding year unsourced." }
    assert_equal "needs_revision", @proposal.reload.status
    assert_equal "needs_more_work", @proposal.latest_review["outcome"]
  end

  test "a rejected proposal cannot be given a review" do
    @proposal.update!(status: "rejected", rejected_at: Time.current)

    post record_review_custom_admin_company_proposal_path(@proposal), params: { review_outcome: "no_change" }

    assert_match(/Reopen it first/, flash[:alert].to_s)
    assert_empty @proposal.reload.review_log
  end

  # ---- logo --------------------------------------------------------------

  test "a logo URL can be set on a proposal" do
    patch custom_admin_company_proposal_path(@proposal), params: { company_proposal: { final_changes: { name: "Zephyr", logo_url: "https://zephyr.example/logo.png" } } }

    assert_redirected_to custom_admin_company_proposal_path(@proposal)
    assert_equal "https://zephyr.example/logo.png", @proposal.reload.final_changes["logo_url"]
  end

  test "a logo URL that is not a web address is refused" do
    patch custom_admin_company_proposal_path(@proposal), params: { company_proposal: { final_changes: { name: "Zephyr", logo_url: "javascript:alert(1)" } } }

    assert_response :unprocessable_entity
    assert_nil @proposal.reload.final_changes["logo_url"]
  end
end
