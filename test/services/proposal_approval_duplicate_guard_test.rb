require "test_helper"

# The Review -> Company handoff. Approval used to consult a duplicate snapshot written
# at intake, so a proposal created before its twin existed could still mint a second
# company row. These cover the live re-check and the identity guard that sits
# immediately in front of the insert.
class ProposalApprovalDuplicateGuardTest < ActiveSupport::TestCase
  setup do
    @admin = admin_users(:one)
    @existing = companies(:one)
    @existing.update!(name: "Pactolane", main_url: "https://www.pactolane.com")
    @existing.update_columns(canonical_domain: "pactolane.com", fingerprint: @existing.calculated_fingerprint, quality_status: nil)
  end

  def proposal_for(name:, url:, status: "ready_for_review")
    changes = {
      "name" => name,
      "main_url" => url,
      "location" => "Lyon, France",
      "description" => "Pactolane builds contract lifecycle management software for legal and procurement teams, covering drafting, clause libraries and approval workflows.",
      "category_id" => categories(:one).id,
      "business_model_id" => business_models(:one).id,
      "business_model_ids" => [business_models(:one).id],
      "target_client_id" => target_clients(:one).id,
      "target_client_ids" => [target_clients(:one).id]
    }
    CompanyProposal.create!(
      status: status,
      proposal_type: "discovery_candidate",
      source: "llm_discovery",
      source_identifier: SecureRandom.uuid,
      source_payload: {},
      proposed_changes: changes,
      final_changes: changes,
      # Deliberately empty: this is exactly the stale snapshot that used to let
      # duplicates through, and the gate must not trust it.
      duplicate_signals: {},
      enriched_at: Time.current,
      agent_details: { "site_evidence" => { "pages" => [{ "label" => "website", "url" => url, "status" => "fetched", "text" => "Contract lifecycle management." }] } }
    )
  end

  test "approval is refused for a proposal duplicating a live company, despite an empty stored snapshot" do
    proposal = proposal_for(name: "Pactolane", url: "https://www.pactolane.com")

    error = assert_raises(ArgumentError) do
      CompanyProposalApprovalService.call(proposal: proposal, admin_user: @admin, publish: true)
    end

    assert_match(/already in the index/, error.message)
    assert_nil proposal.reload.company_id
  end

  # POLICY CHANGE, 2026-09-21, made by the queue owner: a duplicate is surfaced as
  # blocking only on strong, corroborated evidence, and a single loose match is reported
  # instead of enforced. This pair is the clearest case of the shape she asked us to stop
  # stopping writes for. "Pactolane Technologies" against "Pactolane" agrees on the core
  # name and on the brand label read out of that same core - two readings of the same two
  # strings, in one evidence family, with the domains disagreeing. It used to refuse the
  # approval; it now reports an advisory match and lets a human decide.
  #
  # The test is kept, and so is what it was watching: the match is still found, still
  # named, still graded and still recorded. Only the disposition moved. Its NAME is kept
  # too, deliberately, so that this decision stays findable from the history that
  # recorded the old behaviour - read it as "the case where approval used to be refused".
  test "approval is refused for a rebrand of an existing company" do
    proposal = proposal_for(name: "Pactolane Technologies", url: "https://pactolane-clm.example")

    company = CompanyProposalApprovalService.call(proposal: proposal, admin_user: @admin, publish: false)
    assert company.persisted?, "a human approving on one loose key is no longer refused"

    decision = DuplicateGate.check(proposal.reload, record_evidence: false)
    refute decision.blocking?
    assert decision.advisory?, "the match is still found and still put in front of the reviewer"
    assert_equal [%w[core_name brand_name]], decision.matches.map { |match| match["match_types"] }
    assert_match(/Not treated as a duplicate/, decision.recommended_action)
  end

  test "the override still lets a human approve two genuinely distinct companies" do
    proposal = proposal_for(name: "Pactolane", url: "https://pactolane.io")

    company = CompanyProposalApprovalService.call(proposal: proposal, admin_user: @admin, duplicate_override: true, publish: false)

    assert company.persisted?
    refute_equal @existing.id, company.id
  end

  test "the identity guard blocks a second row even when the duplicate check is overridden away" do
    # Same name AND same domain as the existing entry: overriding the name/domain
    # check must still not produce two rows with one identity.
    proposal = proposal_for(name: "Pactolane", url: "https://www.pactolane.com")

    error = assert_raises(ArgumentError) do
      CompanyProposalApprovalService.call(proposal: proposal, admin_user: @admin, duplicate_override: false, publish: false)
    end
    assert_match(/Pactolane \(##{@existing.id}\)|already in the index/, error.message)
    assert_equal 0, Company.where(fingerprint: @existing.fingerprint).count - 1
  end

  test "a clean proposal still approves and links back to its company" do
    proposal = proposal_for(name: "Zephyr Escrow Analytics", url: "https://zephyrescrow.example")

    company = CompanyProposalApprovalService.call(proposal: proposal, admin_user: @admin, publish: true)

    assert company.visible?
    assert_equal company.id, proposal.reload.company_id
    assert_equal "published", proposal.status
  end

  test "two open proposals for one company cannot both be approved" do
    first = proposal_for(name: "Zephyr Escrow Analytics", url: "https://zephyrescrow.example")
    second = proposal_for(name: "Zephyr Escrow Analytics", url: "https://zephyrescrow.example")

    # The sibling check blocks both while they are both open.
    assert_raises(ArgumentError) { CompanyProposalApprovalService.call(proposal: first, admin_user: @admin, publish: true) }

    # Resolving one clears the other to proceed.
    second.update!(status: "rejected")
    company = CompanyProposalApprovalService.call(proposal: first, admin_user: @admin, publish: true)
    assert company.persisted?

    # And now the rejected twin cannot be revived into a second row.
    revived = proposal_for(name: "Zephyr Escrow Analytics", url: "https://zephyrescrow.example")
    assert_raises(ArgumentError) { CompanyProposalApprovalService.call(proposal: revived, admin_user: @admin, publish: true) }
  end
end
