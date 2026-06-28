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

  test "suggestion intake rejects unsupported issue types" do
    assert_raises(ArgumentError, match: /not supported/i) do
      UserSuggestionIntakeService.call(
        company: @company,
        suggestion: {
          issue_type: "spam_issue",
          message: "Founded year should be 2014.",
          submitter_email: "reviewer@example.com"
        }
      )
    end
  end

  test "suggestion intake rejects short messages" do
    assert_raises(ArgumentError, match: /too short/i) do
      UserSuggestionIntakeService.call(
        company: @company,
        suggestion: {
          issue_type: "incorrect_details",
          message: "Too short",
          submitter_email: "reviewer@example.com"
        }
      )
    end
  end

  test "contribution form rejects short descriptions" do
    form = valid_contribution_form
    form.description = "Too short."

    assert_not form.valid?
    assert_includes form.errors[:description], "must be at least 30 characters"
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

  test "processor interprets suggestions even when triage queues for review" do
    proposal = user_suggestion_proposal(
      message: "Founded year should be 2014.",
      founded_date: @company.founded_date
    )

    CompanyUserSubmissionProcessorService.call(proposal: proposal)

    proposal.reload
    assert_equal "ready_for_review", proposal.status
    assert_equal "review", proposal.agent_details.dig("triage", "verdict")
    assert_equal "2014", proposal.agent_details.dig("suggestion_interpretation", "delta", "founded_date")
    assert_equal "2014", proposal.final_changes["founded_date"]
  end

  test "processor auto-applies interpreted suggestions when triage accepts" do
    with_env("USER_SUGGESTION_AUTO_APPLY" => "true") do
      proposal = user_suggestion_proposal(
        message: "Founded year should be 2014.",
        founded_date: @company.founded_date
      )

      triage_accept = { "verdict" => "accept", "confidence" => 0.95, "mode" => "test", "reason" => "Clear factual correction." }
      original_call = UserSubmissionTriageService.method(:call)
      UserSubmissionTriageService.define_singleton_method(:call) { |proposal:| triage_accept }
      begin
        CompanyUserSubmissionProcessorService.call(proposal: proposal)
      ensure
        UserSubmissionTriageService.define_singleton_method(:call, original_call)
      end

      proposal.reload
      assert_equal "published", proposal.status
      assert_equal "2014", @company.reload.founded_date
    end
  end

  test "processor does not auto-apply suggestions when triage queues for review" do
    with_env("USER_SUGGESTION_AUTO_APPLY" => "true") do
      proposal = user_suggestion_proposal(
        message: "Founded year should be 2014.",
        founded_date: @company.founded_date
      )

      CompanyUserSubmissionProcessorService.call(proposal: proposal)

      proposal.reload
      assert_equal "ready_for_review", proposal.status
      assert_not_equal "2014", @company.reload.founded_date
    end
  end

  test "processor leaves ambiguous suggestions for manual review" do
    with_env("USER_SUGGESTION_AUTO_APPLY" => "true") do
      proposal = user_suggestion_proposal(
        message: "Please improve the company description.",
        founded_date: @company.founded_date
      )

      CompanyUserSubmissionProcessorService.call(proposal: proposal)

      proposal.reload
      assert_equal "ready_for_review", proposal.status
      assert_equal({}, proposal.agent_details.dig("suggestion_interpretation", "delta"))
      assert_equal @company.founded_date, proposal.final_changes["founded_date"]
    end
  end

  test "processor rejects spam suggestions without interpretation" do
    proposal = user_suggestion_proposal(
      message: "Buy viagra cheap casino now",
      founded_date: @company.founded_date
    )

    CompanyUserSubmissionProcessorService.call(proposal: proposal)

    proposal.reload
    assert_equal "rejected", proposal.status
    assert_nil proposal.agent_details["suggestion_interpretation"]
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

  def user_suggestion_proposal(message:, founded_date:)
    snapshot = {
      "name" => @company.name,
      "main_url" => @company.main_url,
      "location" => @company.location,
      "founded_date" => founded_date,
      "status" => @company.status,
      "description" => @company.description,
      "category_id" => @company.category_id,
      "business_model_id" => @company.business_model_id,
      "target_client_id" => @company.target_client_id
    }

    CompanyProposal.create!(
      status: "pending",
      proposal_type: "user_suggestion",
      source: "user_suggestion",
      source_identifier: SecureRandom.uuid,
      company: @company,
      submitter_email: "reviewer@example.com",
      issue_type: "incorrect_details",
      user_message: message,
      source_payload: { "company_id" => @company.id },
      proposed_changes: snapshot,
      final_changes: snapshot
    )
  end

  def with_env(vars)
    previous = {}
    vars.each do |key, value|
      previous[key] = ENV[key]
      ENV[key] = value
    end
    yield
  ensure
    previous.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
