require "test_helper"

# A proposal that is plausible but incomplete is handed back to its contributor from the
# Review Tab, not from the Company Tab. The distinction that matters: no company row is
# created on the way, so the record is not on anyone's company queue and there is no
# draft to undo if the contributor never answers.
class CompanyProposalReturnServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @admin = admin_users(:one)
    @proposal = returnable_proposal
  end

  def returnable_proposal(status: "ready_for_review", email: "founder@pactolane.example")
    changes = {
      "name" => "Pactolane", "main_url" => "https://www.pactolane.example",
      "description" => "Pactolane builds contract lifecycle management software for legal teams.",
      "location" => "Lyon, France"
    }
    CompanyProposal.create!(
      status: status, proposal_type: "user_contribution", source: "user_contribution",
      source_identifier: SecureRandom.uuid, source_payload: {}, submitter_email: email,
      proposed_changes: changes, final_changes: changes, duplicate_signals: {}
    )
  end

  # ---- the core of the ask: no company row is minted ----------------------

  test "returning a proposal parks it with instructions and creates no company" do
    assert_no_difference "Company.count" do
      CompanyProposalReturnService.call(
        proposal: @proposal, admin_user: @admin,
        instructions: "The website returns a 404 — please supply a current URL.",
        fields: %w[main_url founded_date]
      )
    end

    @proposal.reload
    assert_equal "needs_revision", @proposal.status
    assert_nil @proposal.company_id, "the proposal is still a proposal"
    assert_equal @admin.id, @proposal.admin_user_id
    assert @proposal.reviewed_at.present?

    request = @proposal.agent_details["current_contributor_request"]
    assert_equal "awaiting_contributor", request["state"]
    assert_equal "The website returns a 404 — please supply a current URL.", request["instructions"]
    assert_equal %w[main_url founded_date], request["fields"]
    assert_equal "founder@pactolane.example", request["contributor_email"]
    assert_equal @admin.email, request["requested_by"]
    assert_equal 1, Array(@proposal.agent_details["contributor_requests"]).size
  end

  test "a returned proposal is still in the review queue, off the reviewer's default view" do
    CompanyProposalReturnService.call(proposal: @proposal, admin_user: @admin, instructions: "Please confirm the founding year.")

    assert_includes CompanyProposal.pending_review, @proposal.reload
    assert_includes CompanyProposal.pending_review.awaiting_contributor, @proposal
    refute_includes CompanyProposal.pending_review.not_awaiting_contributor, @proposal
  end

  test "each round is appended, so earlier requests stay readable" do
    CompanyProposalReturnService.call(proposal: @proposal, admin_user: @admin, instructions: "Round one: supply a current URL.")
    CompanyProposalReturnService.call(proposal: @proposal.reload, admin_user: @admin, instructions: "Round two: the new URL is a parking page.")

    requests = Array(@proposal.reload.agent_details["contributor_requests"])
    assert_equal 2, requests.size
    assert_equal "Round one: supply a current URL.", requests.first["instructions"]
    assert_equal "Round two: the new URL is a parking page.", @proposal.agent_details.dig("current_contributor_request", "instructions")
  end

  # The service writes with update!, so before the uniqueness rule was made conditional a
  # return froze on a proposal whose source_identifier already matched another row's. The
  # collision is planted with update_columns because there is still no unique index and
  # validation would refuse to create the state that real discovery runs produce.
  test "a proposal whose source_identifier already collides can still be returned" do
    twin = returnable_proposal
    twin.update_columns(source_identifier: @proposal.source_identifier)
    collided_identifier = twin.source_identifier

    CompanyProposalReturnService.call(
      proposal: twin, admin_user: @admin,
      instructions: "The description does not say what the product does."
    )

    twin.reload
    assert_equal "needs_revision", twin.status
    assert_equal collided_identifier, twin.source_identifier, "the identity is untouched by a return"

    request = twin.agent_details["current_contributor_request"]
    assert_equal "awaiting_contributor", request["state"]
    assert_equal "The description does not say what the product does.", request["instructions"]
  end

  # ---- refusals write nothing ---------------------------------------------

  test "blank instructions are refused and nothing is written" do
    error = assert_raises(ArgumentError) do
      CompanyProposalReturnService.call(proposal: @proposal, admin_user: @admin, instructions: "   ")
    end

    assert_match(/needs to correct or provide/, error.message)
    @proposal.reload
    assert_equal "ready_for_review", @proposal.status
    assert_nil @proposal.agent_details["current_contributor_request"]
    assert_nil @proposal.reviewed_at
  end

  test "a rejected proposal cannot be returned to its contributor" do
    rejected = returnable_proposal(status: "rejected")

    error = assert_raises(ArgumentError) do
      CompanyProposalReturnService.call(proposal: rejected, admin_user: @admin, instructions: "Please supply a current URL.")
    end

    assert_match(/left the review queue/, error.message)
    assert_equal "rejected", rejected.reload.status
    assert_nil rejected.agent_details["current_contributor_request"]
  end

  test "an approved proposal cannot be returned to its contributor" do
    %w[approved_to_draft published].each do |status|
      approved = returnable_proposal(status: status)

      error = assert_raises(ArgumentError) do
        CompanyProposalReturnService.call(proposal: approved, admin_user: @admin, instructions: "Please supply a current URL.")
      end

      assert_match(/already been approved/, error.message)
      assert_equal status, approved.reload.status
      assert_nil approved.agent_details["current_contributor_request"]
    end
  end

  # ---- the write is confirmed, not assumed --------------------------------

  test "a write that reports success but saves nothing is reported as a failure" do
    error = assert_raises(CompanyProposalReturnService::NotConfirmed) do
      @proposal.stub(:update!, true) do
        CompanyProposalReturnService.call(proposal: @proposal, admin_user: @admin, instructions: "Please supply a current URL.")
      end
    end

    assert_match(/reported success, but the value was not saved/, error.message)
    assert_includes error.unconfirmed.keys, "status"
    assert_equal "needs_revision", error.unconfirmed["status"]["requested"]
    assert_equal "ready_for_review", error.unconfirmed["status"]["saved"]
  end

  # ---- enrichment stands down, with no company row in play ----------------

  test "enrichment refuses a proposal waiting on its contributor even with no company row" do
    CompanyProposalReturnService.call(proposal: @proposal, admin_user: @admin, instructions: "Please supply a current URL.")
    @proposal.reload
    assert_nil @proposal.company_id

    # reviewed_at also locks enrichment, so it is cleared here to prove the protection
    # rests on the proposal's own outstanding request rather than on a timestamp any
    # later write could reset.
    @proposal.update_columns(reviewed_at: nil)

    error = assert_raises(CompanyProposalEnrichmentService::Locked) do
      CompanyProposalEnrichmentService.call(proposal: @proposal, admin_user: nil)
    end
    assert_match(/waiting on its contributor/, error.message)
  end

  test "a returned proposal is not treated as terminal" do
    refute_includes CompanyProposalEnrichmentService::TERMINAL_STATUSES, "needs_revision"
  end

  # ---- the round trip: the contributor answers ----------------------------

  # The submission identity is stable for the same company from the same submitter, so a
  # resubmission has always landed on the row that already exists — and its payload was
  # always thrown away. For a record a reviewer explicitly asked to have fixed, that
  # payload is the whole point.
  test "a resubmission onto a returned proposal updates that row and puts it back in front of a reviewer" do
    original = UserContributionIntakeService.call(form: contribution_form)
    CompanyProposalReturnService.call(
      proposal: original, admin_user: @admin,
      instructions: "The description does not say what the product does.", fields: %w[description]
    )

    resubmitted_form = contribution_form
    resubmitted_form.description = "Pactolane automates contract review and renewal tracking for in-house legal teams."

    again = nil
    assert_no_difference "CompanyProposal.count" do
      assert_no_difference "Company.count" do
        assert_enqueued_with(job: UserContributionProcessingJob) do
          again = UserContributionIntakeService.call(form: resubmitted_form)
        end
      end
    end

    assert_equal original.id, again.id, "the resubmission lands on the same row"
    again.reload
    assert_equal "ready_for_review", again.status
    assert_equal "Pactolane automates contract review and renewal tracking for in-house legal teams.", again.final_changes["description"]
    assert_nil again.agent_details["current_contributor_request"], "the request is answered"
    assert_equal 1, Array(again.agent_details["contributor_requests"]).size, "the history of what was asked survives"
    assert_equal 1, Array(again.agent_details["contributor_resubmissions"]).size
    assert_includes CompanyProposal.pending_review.not_awaiting_contributor, again, "back on the reviewer's default view"
  end

  test "a repeat submission of a proposal nobody asked to have fixed is still discarded" do
    original = UserContributionIntakeService.call(form: contribution_form)
    original.update!(status: "ready_for_review")

    repeat_form = contribution_form
    repeat_form.description = "A second description that must not overwrite the first."

    again = nil
    assert_no_difference "CompanyProposal.count" do
      again = UserContributionIntakeService.call(form: repeat_form)
    end

    assert_equal original.id, again.id
    refute_equal "A second description that must not overwrite the first.", again.reload.final_changes["description"]
  end

  def contribution_form
    CompanyContributionForm.new(
      contact_email: "founder@pactolane.example",
      contact_name: "Ada Contributor",
      name: "Pactolane",
      main_url: "https://www.pactolane.example",
      location: "Lyon, France",
      founded_date: "2024",
      category_id: categories(:one).id,
      description: "Contract workflow software for in-house legal teams.",
      status: "active",
      business_model_ids: [business_models(:one).id],
      target_client_ids: [target_clients(:one).id],
      tag_names: ["artificial intelligence"]
    )
  end
end
