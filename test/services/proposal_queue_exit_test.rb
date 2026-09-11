require "test_helper"

# A proposal that has become a company draft has left the Review queue. Two live
# representations of one piece of work — the draft under Company review and the
# proposal still under Review — is how a reviewer ends up doing the same job twice and
# trusting neither queue's count.
class ProposalQueueExitTest < ActiveSupport::TestCase
  GOOD = "Zephyr builds escrow reconciliation software for law firms, covering client-account ledgers and three-way reconciliation.".freeze

  setup do
    @admin = admin_users(:one)
  end

  def proposal(status: "ready_for_review", **attrs)
    changes = { "name" => "Zephyr Escrow", "main_url" => "https://zephyrescrow.example", "description" => GOOD,
                "category_id" => categories(:one).id, "target_client_id" => target_clients(:one).id,
                "business_model_id" => business_models(:one).id, "location" => "Boston, MA" }
    CompanyProposal.create!(
      status: status, proposal_type: "discovery_candidate", source: "llm_discovery",
      source_identifier: SecureRandom.uuid, source_payload: {},
      proposed_changes: changes, final_changes: changes, duplicate_signals: {},
      agent_details: researched_agent_details(url: "https://zephyrescrow.example"), enriched_at: Time.current,
      **attrs
    )
  end

  test "approving into a draft takes the proposal out of every active queue" do
    subject = proposal

    CompanyProposalApprovalService.call(proposal: subject, admin_user: @admin, publish: false)
    subject.reload

    assert_equal "approved_to_draft", subject.status
    assert subject.company_id.present?
    refute_includes CompanyProposal.pending_review, subject
    assert_includes CompanyProposal.approved_to_draft, subject, "still findable, under the status it reached"
  end

  test "the link back to the proposal survives the approval" do
    subject = proposal
    company = CompanyProposalApprovalService.call(proposal: subject, admin_user: @admin, publish: false)
    subject.reload

    assert_equal company.id, subject.company_id
    assert_equal @admin, subject.admin_user
    assert subject.approved_at.present?
    assert_equal subject, CompanyProposal.find(subject.id), "the proposal is transitioned, never deleted"
  end

  # The actual cause of the four proposals found sitting in an active queue with a
  # company already attached: enrichment writes a status, and the reviewer-facing
  # Enrich button passes force, which was overriding the refusal AND the workflow state
  # the refusal existed to protect.
  test "enriching an approved proposal does not put it back in the review queue" do
    subject = proposal
    CompanyProposalApprovalService.call(proposal: subject, admin_user: @admin, publish: false)
    subject.reload
    assert_equal "approved_to_draft", subject.status

    with_site_evidence { CompanyProposalEnrichmentService.call(proposal: subject, admin_user: @admin, force: true) }

    assert_equal "approved_to_draft", subject.reload.status,
                 "force overrides the refusal to enrich, not the fact that this work already left the queue"
    refute_includes CompanyProposal.pending_review, subject
  end

  test "enrichment refuses an approved proposal outright unless forced" do
    subject = proposal
    CompanyProposalApprovalService.call(proposal: subject, admin_user: @admin, publish: false)

    error = assert_raises(CompanyProposalEnrichmentService::Locked) do
      CompanyProposalEnrichmentService.call(proposal: subject.reload, admin_user: @admin)
    end
    assert_match(/already been approved/, error.message)
  end

  test "a published proposal is not dragged back either" do
    subject = proposal
    CompanyProposalApprovalService.call(proposal: subject, admin_user: @admin, publish: true)
    assert_equal "published", subject.reload.status

    with_site_evidence { CompanyProposalEnrichmentService.call(proposal: subject, admin_user: @admin, force: true) }

    assert_equal "published", subject.reload.status
  end

  test "approving twice promotes the existing draft rather than minting a second company" do
    subject = proposal
    company = CompanyProposalApprovalService.call(proposal: subject, admin_user: @admin, publish: false)

    assert_no_difference -> { Company.count } do
      again = CompanyProposalApprovalService.call(proposal: subject.reload, admin_user: @admin, publish: false)
      assert_equal company.id, again.id
    end
  end

  # The recovery path for the records already in this state: a reviewer approving one
  # again is saying the work is done, and that has to actually clear it.
  test "approving a proposal stranded in an open status clears it from the queue" do
    subject = proposal
    company = CompanyProposalApprovalService.call(proposal: subject, admin_user: @admin, publish: false)
    subject.update_columns(status: "ready_for_review")
    assert_includes CompanyProposal.pending_review, subject.reload

    CompanyProposalApprovalService.call(proposal: subject, admin_user: @admin, publish: false)

    assert_equal "approved_to_draft", subject.reload.status
    refute_includes CompanyProposal.pending_review, subject
    assert_equal company.id, subject.company_id
  end

  # A company saved without the link back to its proposal is invisible to the
  # idempotence check, so the next approval would mint a second one.
  test "a failure while linking the proposal leaves no orphaned company behind" do
    subject = proposal

    assert_no_difference -> { Company.count } do
      assert_raises(ActiveRecord::RecordInvalid) do
        subject.stub(:update!, ->(*) { raise ActiveRecord::RecordInvalid, subject }) do
          CompanyProposalApprovalService.call(proposal: subject, admin_user: @admin, publish: false)
        end
      end
    end

    assert_nil subject.reload.company_id
    assert_includes CompanyProposal.pending_review, subject, "it stays reviewable rather than vanishing"
  end
end
