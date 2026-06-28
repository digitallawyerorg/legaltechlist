require "test_helper"

class UserSubmissionWorkflowTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @company = companies(:one)
  end

  test "contribution form requires contact name" do
    form = valid_contribution_form
    form.contact_name = nil

    assert_not form.valid?
    assert_includes form.errors[:contact_name], "can't be blank"
  end

  test "contribution form requires contact email" do
    form = valid_contribution_form
    form.contact_email = nil

    assert_not form.valid?
    assert_includes form.errors[:contact_email], "can't be blank"
  end

  test "contribution form requires at least one discoverable tag" do
    form = valid_contribution_form
    form.tag_names = []

    assert_not form.valid?
    assert_includes form.errors[:tag_names], "can't be blank"
  end

  test "contribution form rejects non-curated tags" do
    form = valid_contribution_form
    form.tag_names = ["saas"]

    assert_not form.valid?
    assert_includes form.errors[:tag_names], "must be selected from the curated tag list"
  end

  test "contribution intake creates proposal not company" do
    form = valid_contribution_form

    assert_no_difference "Company.count" do
      assert_difference "CompanyProposal.count", 1 do
        assert_enqueued_with(job: UserContributionProcessingJob) do
          proposal = UserContributionIntakeService.call(form: form)
          assert_equal "user_contribution", proposal.proposal_type
          assert_equal "pending", proposal.status
          assert_equal "contributor@example.com", proposal.submitter_email
        end
      end
    end
  end

  test "suggestion intake creates linked proposal" do
    assert_no_difference "Company.count" do
      assert_difference "CompanyProposal.count", 1 do
        proposal = UserSuggestionIntakeService.call(
          company: @company,
          suggestion: {
            issue_type: "incorrect_details",
            message: "Founded year should be 2014.",
            submitter_email: "reviewer@example.com"
          }
        )
        assert_equal "user_suggestion", proposal.proposal_type
        assert_equal @company.id, proposal.company_id
        assert_equal "incorrect_details", proposal.issue_type
      end
    end
  end

  test "suggestion intake requires submitter email" do
    assert_raises(ArgumentError, match: /email/i) do
      UserSuggestionIntakeService.call(
        company: @company,
        suggestion: {
          issue_type: "incorrect_details",
          message: "Founded year should be 2014.",
          submitter_email: ""
        }
      )
    end
  end

  test "triage rejects obvious spam without enrichment" do
    proposal = user_contribution_proposal(description: "Buy viagra cheap casino now")

    CompanyUserSubmissionProcessorService.call(proposal: proposal)

    proposal.reload
    assert_equal "rejected", proposal.status
    assert_equal "reject", proposal.agent_details.dig("triage", "verdict")
    assert_nil proposal.enriched_at
  end

  test "processor queues uncertain submissions for review" do
    proposal = user_contribution_proposal(description: "We are the best leading world-class revolutionary legal platform.")

    CompanyUserSubmissionProcessorService.call(proposal: proposal)

    assert_equal "ready_for_review", proposal.reload.status
    assert_equal "review", proposal.agent_details.dig("triage", "verdict")
  end

  test "apply update service updates existing company for user suggestion" do
    proposal = CompanyProposal.create!(
      status: "ready_for_review",
      proposal_type: "user_suggestion",
      source: "user_suggestion",
      source_identifier: SecureRandom.uuid,
      company: @company,
      submitter_email: "reviewer@example.com",
      issue_type: "incorrect_details",
      user_message: "Founded year should be 2014.",
      source_payload: {},
      proposed_changes: { "name" => @company.name },
      final_changes: { "name" => @company.name, "founded_date" => "2014" }
    )

    CompanyProposalApplyUpdateService.call(proposal: proposal, admin_user: admin_users(:one))

    assert_equal "2014", @company.reload.founded_date
    assert_equal "published", proposal.reload.status
  end

  private

  def valid_contribution_form
    CompanyContributionForm.new(
      contact_email: "contributor@example.com",
      contact_name: "Ada Contributor",
      name: "New Legal Startup",
      main_url: "https://new-legal-startup.example",
      location: "Palo Alto, CA",
      founded_date: "2024",
      category_id: categories(:one).id,
      description: "Contract workflow software for in-house teams.",
      status: "active",
      business_model_ids: [business_models(:one).id],
      target_client_ids: [target_clients(:one).id],
      tag_names: ["artificial intelligence"]
    )
  end

  def user_contribution_proposal(description:)
    CompanyProposal.create!(
      status: "pending",
      proposal_type: "user_contribution",
      source: "user_contribution",
      source_identifier: SecureRandom.uuid,
      submitter_email: "spam@example.com",
      source_payload: {},
      proposed_changes: {
        "name" => "Spam Co",
        "main_url" => "https://spam-#{SecureRandom.hex(4)}.example",
        "description" => description
      },
      final_changes: {
        "name" => "Spam Co",
        "main_url" => "https://spam-#{SecureRandom.hex(4)}.example",
        "description" => description
      }
    )
  end
end
