require "test_helper"

# A proposal's source_identifier is its intake identity, and the uniqueness rule around
# it used to be re-judged on every save. A pair that already collided — created in the
# same second by one discovery run — could therefore not be saved at all, which is the
# same race UserContributionIntakeService hardened its own identity against (see the
# twins "1, 21 and 49 seconds apart" note at that service's #call).
class CompanyProposalTest < ActiveSupport::TestCase
  def proposal(**attrs)
    CompanyProposal.create!(
      status: "ready_for_review", proposal_type: "discovery_candidate", source: "llm_discovery",
      source_identifier: SecureRandom.uuid, source_payload: {}, duplicate_signals: {},
      proposed_changes: { "name" => "Zephyr" }, final_changes: { "name" => "Zephyr" },
      **attrs
    )
  end

  # Every disposition path writes through the record — reject, the reject_proposal tool,
  # DuplicateMergeService, the return to a contributor — so a save that leaves the
  # identifier alone has to go through regardless of who else holds the value.
  test "a record already holding a colliding identifier can still be saved" do
    first = proposal
    second = proposal
    second.update_columns(source_identifier: first.source_identifier)

    second.status = "rejected"

    assert second.save, second.errors.full_messages.to_sentence
    assert_equal "rejected", second.reload.status
  end

  test "a newly colliding identifier is still refused" do
    taken = proposal.source_identifier

    twin = CompanyProposal.new(
      status: "pending", proposal_type: "discovery_candidate", source: "llm_discovery",
      source_identifier: taken, source_payload: {}, duplicate_signals: {},
      proposed_changes: {}, final_changes: {}
    )

    refute twin.valid?
    assert_includes twin.errors.full_messages, "Source identifier has already been taken"
  end

  test "moving an existing record onto an identifier another row holds is refused" do
    taken = proposal.source_identifier
    other = proposal

    other.source_identifier = taken

    refute other.valid?, "renaming into a collision is still a collision"
  end
end
