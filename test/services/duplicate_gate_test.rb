require "test_helper"

# One gate, every ingestion path. Duplicate detection used to be four separate checks and
# one hole: the approval tool sent user suggestions straight to the apply service, past the
# quality gate and the duplicate check both, and the apply service had no check of its own
# — so an auto-applied suggestion overwrote a published record while its twin sat blocking
# in the queue (proposal 4175 over 4174). These cover the gate from each path that reaches
# it, plus the two things it must never do: block a suggestion against its own company, or
# block two companies that merely share a word.
class DuplicateGateTest < ActiveSupport::TestCase
  setup do
    @admin = admin_users(:one)
    AdminUser.find_or_create_by!(email: Mcp::CuratorActor.email) do |user|
      user.password = "password123"
      user.password_confirmation = "password123"
    end
    @company = companies(:one)
    @company.update!(name: "Caseway", main_url: "https://caseway.ai")
    @company.update_columns(canonical_domain: "caseway.ai", visible: true, quality_status: nil,
                            fingerprint: @company.calculated_fingerprint)
  end

  # ---- helpers -----------------------------------------------------------

  def suggestion(name: "Caseway", url: "https://caseway.ai", company: @company, message: "Founded year should be 2014.", **changes)
    snapshot = {
      "name" => name,
      "main_url" => url,
      "location" => company.location,
      "founded_date" => company.founded_date,
      "status" => company.status,
      "description" => company.description,
      "category_id" => company.category_id,
      "business_model_id" => company.business_model_id,
      "target_client_id" => company.target_client_id
    }.merge(changes)

    CompanyProposal.create!(
      status: "pending",
      proposal_type: "user_suggestion",
      source: "user_suggestion",
      source_identifier: SecureRandom.uuid,
      company: company,
      submitter_email: "reader@example.org",
      issue_type: "incorrect_details",
      user_message: message,
      source_payload: { "company_id" => company.id },
      proposed_changes: snapshot,
      final_changes: snapshot
    )
  end

  # The competing record: a second, unlinked proposal covering the same entity, open in the
  # queue. This is the shape that was blocking 4175 and was never consulted.
  def competing_proposal(name: "Caseway", url: "https://caseway.ai")
    changes = { "name" => name, "main_url" => url, "description" => "Litigation research assistant for civil practitioners." }
    CompanyProposal.create!(
      status: "ready_for_review",
      proposal_type: "user_contribution",
      source: "user_contribution",
      source_identifier: SecureRandom.uuid,
      submitter_email: "founder@caseway.ai",
      source_payload: {},
      proposed_changes: changes,
      final_changes: changes
    )
  end

  def with_env(vars)
    previous = {}
    vars.each { |key, value| previous[key] = ENV[key]; ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  # ---- the auto-apply path, which used to skip the gate entirely ---------

  # Proposal 4175: a suggestion against a company it was already linked to, auto-applied
  # and published five seconds after its twin 4174 was created carrying the blocking
  # match. Nothing on this path asked.
  test "auto-apply stops and routes when a competing proposal carries a blocking match" do
    with_env("USER_SUGGESTION_AUTO_APPLY" => "true") do
      twin = competing_proposal
      proposal = suggestion
      description_before = @company.description

      result = CompanyUserSubmissionProcessorService.call(proposal: proposal)
      proposal.reload

      assert_equal "duplicate_resolution", result["status"]
      refute_equal "published", proposal.status, "an auto-apply may not publish over a blocking duplicate"
      assert_equal "ready_for_review", proposal.status
      assert_equal description_before, @company.reload.description, "the live record must not be overwritten"
      refute_equal "2014", @company.reload.founded_date
      assert_nil proposal.agent_details["suggestion_interpretation"],
                 "the gate stops the path before any automated step reads or rewrites the submission"
      assert_equal twin.id, proposal.agent_details.dig("duplicate_routing", "canonical_proposal_id")
    end
  end

  test "a routed auto-apply lands in the admin duplicate queue" do
    with_env("USER_SUGGESTION_AUTO_APPLY" => "true") do
      competing_proposal
      proposal = suggestion

      CompanyUserSubmissionProcessorService.call(proposal: proposal)

      assert_includes CompanyProposal.pending_review.map(&:id), proposal.reload.id
      assert proposal.duplicate_blocking?, "the duplicate queue selects live over open work"
      assert_match(/Routed to duplicate resolution/, proposal.reviewer_notes)
    end
  end

  # The evidence has to outlive the live view: resolving the twin drops it from the
  # comparison set, and a later reader would otherwise conclude the stop never happened.
  test "a stopped auto-apply records what the gate saw" do
    with_env("USER_SUGGESTION_AUTO_APPLY" => "true") do
      twin = competing_proposal
      proposal = suggestion

      CompanyUserSubmissionProcessorService.call(proposal: proposal)
      twin.update!(status: "rejected")

      evidence = proposal.reload.duplicate_evidence
      assert_equal 1, evidence.size
      assert_equal twin.id, evidence.first["matched"].first["proposal_id"]
    end
  end

  # ---- the same gate from every other path -------------------------------

  test "the apply service refuses and routes a blocking suggestion, whoever calls it" do
    competing_proposal
    proposal = suggestion

    error = assert_raises(DuplicateGate::Blocked) do
      CompanyProposalApplyUpdateService.call(proposal: proposal, admin_user: @admin, publish: true)
    end

    assert_match(/Resolve the duplicate/, error.message)
    refute_equal "published", proposal.reload.status
    assert_equal "ready_for_review", proposal.status
  end

  test "the approval tool reports a blocking suggestion as routed, not applied" do
    competing_proposal
    proposal = suggestion

    response = Mcp::Tools::ApproveProposalTool.call(server_context: { actor: "test" }, id: proposal.id, human_approved: true)
    payload = JSON.parse(response.to_h[:content].first[:text])

    assert_equal "duplicate_resolution", payload["result"]
    assert_equal false, payload["applied_update"]
    assert_equal false, payload["published"]
    assert_equal false, payload["retryable"]
    assert payload["duplicate_blocking"]
  end

  # The override is the human saying "these are genuinely different companies". It is the
  # only way past the gate, and it is not available to an autonomous path.
  test "a human override still applies the suggestion" do
    competing_proposal
    proposal = suggestion("description" => "Litigation research for civil practitioners, with clause-level citations.")

    company = CompanyProposalApplyUpdateService.call(proposal: proposal, admin_user: @admin, publish: true, duplicate_override: true)

    assert_equal "Litigation research for civil practitioners, with clause-level citations.", company.reload.description
    assert_equal "published", proposal.reload.status
  end

  test "the override does not erase the evidence the gate collected" do
    competing_proposal
    proposal = suggestion

    CompanyProposalApplyUpdateService.call(proposal: proposal, admin_user: @admin, publish: true, duplicate_override: true)

    assert_equal 1, proposal.reload.duplicate_evidence.size
  end

  # Nothing tells the submitter their suggestion was approved, because it was not: the
  # record is open work in the duplicate queue and a human still owes them the comparison.
  test "a stopped auto-apply announces no decision" do
    with_env("USER_SUGGESTION_AUTO_APPLY" => "true") do
      competing_proposal
      proposal = suggestion
      decisions = []

      SlackNotifier.stub(:contribution_decision, ->(_proposal, **kwargs) { decisions << kwargs[:decision] }) do
        CompanyUserSubmissionProcessorService.call(proposal: proposal)
      end

      assert_empty decisions, "a duplicate is neither an approval nor a rejection"
    end
  end

  # A blocked approval used to refuse and leave the proposal exactly where it was, so the
  # next run made the same attempt. Every path now leaves it somewhere a human will see it.
  test "a blocked approval routes the proposal rather than only refusing" do
    proposal = competing_proposal

    assert_raises(DuplicateGate::Blocked) do
      CompanyProposalApprovalService.call(proposal: proposal, admin_user: @admin, publish: true)
    end

    proposal.reload
    assert_nil proposal.company_id, "no second row"
    assert_equal "ready_for_review", proposal.status
    assert_equal @company.id, proposal.agent_details.dig("duplicate_routing", "canonical_company_id")
    assert_match(/Routed to duplicate resolution/, proposal.reviewer_notes)
  end

  test "the discovery path asks the same gate" do
    proposal = competing_proposal(name: "Caseway", url: "https://caseway.ai")

    assert DuplicateGate.check(proposal).blocking?
    assert_equal @company.id, DuplicateGate.check(proposal).canonical_match["id"]
  end

  test "the quality report reads the gate without resolving or recording anything" do
    competing_proposal
    proposal = suggestion

    proposal.refresh_duplicate_signals!
    report = CompanyProposalQualityService.call(proposal)

    refute report["publish_ready"]
    assert report["blockers"].any? { |blocker| blocker.match?(/covers the same company|already in the index/) }
  end

  # ---- routing is idempotent ---------------------------------------------

  test "re-attempting a blocked apply does not stack the same note" do
    competing_proposal
    proposal = suggestion

    2.times do
      assert_raises(DuplicateGate::Blocked) do
        CompanyProposalApplyUpdateService.call(proposal: proposal, admin_user: @admin, publish: true)
      end
    end

    assert_equal 1, proposal.reload.reviewer_notes.scan(/Routed to duplicate resolution/).size
  end

  # A blocked approval is a refusal, not a rollback: a proposal that already minted its
  # company keeps the status it earned.
  test "routing does not reopen a proposal that already resolved" do
    competing_proposal
    proposal = suggestion
    proposal.update!(status: "published")

    DuplicateGate.route!(DuplicateGate.check(proposal))

    assert_equal "published", proposal.reload.status
    assert proposal.agent_details["duplicate_routing"].present?
  end

  # ---- what the gate must not block --------------------------------------

  # The suggestion is bound to its company; matching that company is the record commenting
  # on itself. Blocking this would mean no published entry could ever be corrected.
  test "a suggestion against its own linked company still auto-applies" do
    with_env("USER_SUGGESTION_AUTO_APPLY" => "true") do
      proposal = suggestion

      result = CompanyUserSubmissionProcessorService.call(proposal: proposal)

      assert_equal "applied", result["status"]
      assert_equal "published", proposal.reload.status
      assert_equal "2014", @company.reload.founded_date
    end
  end

  test "a suggestion against its own company is not blocked by the apply service either" do
    proposal = suggestion

    refute DuplicateGate.check(proposal).blocking?
    assert_nothing_raised { CompanyProposalApplyUpdateService.call(proposal: proposal, admin_user: @admin, publish: true) }
  end

  # Contracts 365 against Cloud Contracts 365: two companies, and a suggestion naming one
  # of them must still reach the record it is about.
  test "a competing proposal that merely shares a word does not block the apply" do
    with_env("USER_SUGGESTION_AUTO_APPLY" => "true") do
      competing_proposal(name: "Cloud Caseway 365", url: "https://cloudcaseway365.example")
      proposal = suggestion

      result = CompanyUserSubmissionProcessorService.call(proposal: proposal)

      assert_equal "applied", result["status"]
      assert_equal "2014", @company.reload.founded_date
    end
  end
end
