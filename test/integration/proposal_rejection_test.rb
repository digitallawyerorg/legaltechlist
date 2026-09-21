require "test_helper"

# Rejecting a duplicate is the last step of resolving one, and it was the step that
# failed: a 422 rendered in the public site's chrome, saying the session may have
# expired or the form may have been submitted twice, with no way back into the queue
# and no indication which of those had actually happened.
class ProposalRejectionTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in admin_users(:one)
    @proposal = CompanyProposal.create!(
      status: "ready_for_review", proposal_type: "discovery_candidate", source: "llm_discovery",
      source_identifier: SecureRandom.uuid, source_payload: {}, duplicate_signals: {},
      proposed_changes: { "name" => "Zephyr" }, final_changes: { "name" => "Zephyr" }
    )
  end

  QUEUE = { "status" => "duplicate", "page" => "2" }.freeze

  test "rejecting once resolves the proposal and returns to the queue it came from" do
    post reject_custom_admin_company_proposal_path(@proposal), params: { return_status: "duplicate", queue: QUEUE }

    assert_response :redirect
    assert_includes @response.headers["Location"], "/admin/proposals"
    assert_equal "rejected", @proposal.reload.status
    refute_includes CompanyProposal.pending_review, @proposal
  end

  # The second request is the one that produced the 422. It cannot be allowed to
  # overwrite the first decision, and it is not an error worth an error page.
  test "rejecting a second time says so rather than failing" do
    post reject_custom_admin_company_proposal_path(@proposal), params: { rejection_reason: "Duplicate of #17270." }
    first_rejected_at = @proposal.reload.rejected_at

    post reject_custom_admin_company_proposal_path(@proposal), params: { rejection_reason: "Something else entirely." }

    assert_response :redirect
    assert_match(/already resolved/, flash[:notice].to_s)
    assert_equal "Duplicate of #17270.", @proposal.reload.rejection_reason, "the original decision stands"
    assert_equal first_rejected_at, @proposal.rejected_at
  end

  test "a repeated rejection does not notify anyone a second time" do
    post reject_custom_admin_company_proposal_path(@proposal)

    SlackNotifier.stub(:contribution_decision, ->(*) { raise "notified twice for one decision" }) do
      post reject_custom_admin_company_proposal_path(@proposal)
    end

    assert_response :redirect
  end

  # An admin whose session aged out was being handed the public 422 page.
  test "an expired session produces an admin error, not the public error page" do
    ActionController::Base.allow_forgery_protection = true
    post reject_custom_admin_company_proposal_path(@proposal), params: { authenticity_token: "stale" }

    assert_response :redirect
    assert_match(/session had expired/, flash[:alert].to_s)
    assert_match(/Nothing was changed/, flash[:alert].to_s)
    assert_equal "ready_for_review", @proposal.reload.status, "a refused request must not change the decision"
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "an expired session sends the reviewer back into the admin, never to the public site" do
    ActionController::Base.allow_forgery_protection = true
    post reject_custom_admin_company_proposal_path(@proposal),
         params: { authenticity_token: "stale" },
         headers: { "HTTP_REFERER" => custom_admin_company_proposals_path(status: "duplicate") }

    assert_response :redirect
    assert_includes @response.headers["Location"], "/admin/proposals"
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  # ---- disposing of a pre-existing identifier collision -------------------

  # One discovery run created two proposals in the same second with the same
  # source_identifier, so the collision predates every disposition. Rejecting
  # re-validated the whole record and refused it — "could not be rejected: Source
  # identifier has already been taken" — leaving both rows stuck in the queue with no
  # way out of it.
  test "a proposal whose identifier already collides can still be rejected" do
    twin = CompanyProposal.create!(
      status: "ready_for_review", proposal_type: "discovery_candidate", source: "llm_discovery",
      source_identifier: SecureRandom.uuid, source_payload: {}, duplicate_signals: {},
      proposed_changes: { "name" => "Zephyr" }, final_changes: { "name" => "Zephyr" }
    )
    # There is no unique index behind the validation, so this is the state the pair is
    # actually in: two rows, one source and one identifier between them.
    twin.update_columns(source_identifier: @proposal.source_identifier)

    post reject_custom_admin_company_proposal_path(@proposal), params: { rejection_reason: "Duplicate of the twin from the same run." }

    assert_response :redirect
    assert_nil flash[:alert]
    assert_equal "rejected", @proposal.reload.status

    post reject_custom_admin_company_proposal_path(twin), params: { rejection_reason: "Same run, same identifier." }

    assert_equal "rejected", twin.reload.status, "both halves of the pair have to be disposable"
  end

  # ---- applying a reviewer's per-field choices ----------------------------

  # The safety property that matters once conflicting fields can be overridden at all:
  # submitting the form without touching anything must never replace a value the index
  # already holds. Gap fills are pre-selected; "Keep existing" is the default for
  # everything else.
  test "submitting the merge form untouched fills gaps and overrides nothing" do
    company = companies(:one)
    company.update!(name: "Pactolane", main_url: "https://www.pactolane.com",
                    description: "Pactolane builds contract lifecycle management software.",
                    location: "Lyon, France")
    company.update_columns(canonical_domain: "pactolane.com", founded_date: nil, quality_status: nil)

    changes = { "name" => "Pactolane", "main_url" => "https://www.pactolane.com",
                "location" => "Paris, France", "founded_date" => "2021" }
    duplicate = CompanyProposal.create!(
      status: "ready_for_review", proposal_type: "user_contribution", source: "user_contribution",
      source_identifier: SecureRandom.uuid, source_payload: {}, duplicate_signals: {},
      proposed_changes: changes, final_changes: changes, enriched_at: Time.current,
      agent_details: researched_agent_details(url: "https://www.pactolane.com")
    )

    # What the form posts when the reviewer changes nothing: the pre-checked gap fill,
    # and "keep" for the field the two records disagree on.
    post merge_duplicate_custom_admin_company_proposal_path(duplicate),
         params: { company_id: company.id, fields: ["founded_date"], field_choice: { "location" => "keep" } }

    company.reload
    assert_equal "2021", company.founded_date, "the gap is filled"
    assert_equal "Lyon, France", company.location, "the default is always to keep what the index holds"
    assert_equal "rejected", duplicate.reload.status
  end

  test "choosing the proposal's value for a disputed field writes it and records both" do
    company = companies(:one)
    company.update!(name: "Pactolane", main_url: "https://www.pactolane.com",
                    description: "Pactolane builds contract lifecycle management software.",
                    location: "Lyon, France")
    company.update_columns(canonical_domain: "pactolane.com", quality_status: nil)

    changes = { "name" => "Pactolane", "main_url" => "https://www.pactolane.com", "location" => "Paris, France" }
    duplicate = CompanyProposal.create!(
      status: "ready_for_review", proposal_type: "user_contribution", source: "user_contribution",
      source_identifier: SecureRandom.uuid, source_payload: {}, duplicate_signals: {},
      proposed_changes: changes, final_changes: changes, enriched_at: Time.current,
      agent_details: researched_agent_details(url: "https://www.pactolane.com")
    )

    post merge_duplicate_custom_admin_company_proposal_path(duplicate),
         params: { company_id: company.id, field_choice: { "location" => "proposal" } }

    assert_equal "Paris, France", company.reload.location
    run = PipelineRun.where(run_type: "duplicate_merge").order(:created_at).last
    assert_equal "Lyon, France", run.details.dig("applied_changes", "location", "from")
    assert_equal %w[location], run.details["overridden_fields"]
    assert_match(/replaced, not filled in/, flash[:notice].to_s,
                 "replacing a value the index held is worth saying out loud")
  end

  # The referrer is attacker-supplied; it is used as a same-origin admin path or not at all.
  test "a referrer pointing off the admin is not followed" do
    ActionController::Base.allow_forgery_protection = true
    post reject_custom_admin_company_proposal_path(@proposal),
         params: { authenticity_token: "stale" },
         headers: { "HTTP_REFERER" => "https://elsewhere.example/admin/proposals" }

    assert_response :redirect
    refute_includes @response.headers["Location"], "elsewhere.example"
  ensure
    ActionController::Base.allow_forgery_protection = false
  end
end
