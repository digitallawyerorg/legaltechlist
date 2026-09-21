require "test_helper"

# The submission identity is a hash of <canonical host || normalized name> | <contact
# email> and nothing else, so two unrelated submissions from one contributor whose URLs
# canonicalise to the same host arrive on the same key. Since a returned record reopens
# in place on that key, a second submission could rename a first contributor's record
# and replace its Source payload — the copy of what was originally submitted — while it
# kept the first submission's drafted description, verification and evidence. These
# tests pin the identity to the submission it belongs to.
class UserContributionResubmissionIdentityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @admin = admin_users(:one)
  end

  test "a different submission sharing one contributor's host and email gets its own row" do
    original = UserContributionIntakeService.call(form: contribution_form)
    original.update!(
      final_changes: original.final_changes.merge("description" => "Pactolane automates contract review and renewal tracking for in-house legal teams."),
      agent_details: original.agent_details.merge("description_verification" => { "status" => "supported", "checked_at" => "2026-09-01T00:00:00Z" })
    )
    CompanyProposalReturnService.call(
      proposal: original, admin_user: @admin,
      instructions: "Please supply the founding year.", fields: %w[founded_date]
    )
    stored_payload = original.reload.source_payload

    # Same contributor, same host, a different company.
    other = contribution_form(
      name: "Verity Redline",
      main_url: "https://pactolane.example/verity",
      description: "Verity Redline is a redlining assistant for commercial contract negotiation teams."
    )

    second = nil
    assert_difference "CompanyProposal.count", 1 do
      second = UserContributionIntakeService.call(form: other)
    end

    refute_equal original.id, second.id, "the second submission must not land on the first one's row"
    refute_equal original.source_identifier, second.source_identifier
    assert_equal "Verity Redline", second.final_changes["name"]

    original.reload
    assert_equal "Pactolane", original.final_changes["name"], "the returned record keeps its own name"
    assert_equal "Pactolane", original.source_payload["name"]
    assert_equal stored_payload, original.source_payload, "the Source payload is the record of what its own contributor submitted"
    assert_equal "Pactolane automates contract review and renewal tracking for in-house legal teams.", original.final_changes["description"]
    assert_equal "supported", original.agent_details.dig("description_verification", "status")
    assert_equal "needs_revision", original.status
    assert_equal "awaiting_contributor", original.agent_details.dig("current_contributor_request", "state"),
      "the first contributor is still the one being waited on"
  end

  test "a genuine resubmission still reopens the same row in place" do
    original = UserContributionIntakeService.call(form: contribution_form)
    CompanyProposalReturnService.call(
      proposal: original, admin_user: @admin,
      instructions: "The description does not say what the product does.", fields: %w[description]
    )

    answered = contribution_form(description: "Pactolane automates contract review and renewal tracking for in-house legal teams.")

    again = nil
    assert_no_difference "CompanyProposal.count" do
      again = UserContributionIntakeService.call(form: answered)
    end

    assert_equal original.id, again.id
    again.reload
    assert_equal "ready_for_review", again.status
    assert_equal "Pactolane automates contract review and renewal tracking for in-house legal teams.", again.final_changes["description"]
    assert_nil again.agent_details["current_contributor_request"], "the request is answered"
    assert_equal 1, Array(again.agent_details["contributor_resubmissions"]).size
  end

  # Identity still has to collapse twins for the record that was pushed off the shared
  # key, or the collision would be traded for the double-submit bug it was added to fix.
  test "a repeat of the submission that got its own identity lands on that row" do
    UserContributionIntakeService.call(form: contribution_form)
    other = contribution_form(
      name: "Verity Redline",
      main_url: "https://pactolane.example/verity",
      description: "Verity Redline is a redlining assistant for commercial contract negotiation teams."
    )
    second = UserContributionIntakeService.call(form: other)

    repeat = nil
    assert_no_difference "CompanyProposal.count" do
      repeat = UserContributionIntakeService.call(form: other.dup)
    end

    assert_equal second.id, repeat.id
  end

  test "the record that got its own identity can itself be returned and resubmitted in place" do
    UserContributionIntakeService.call(form: contribution_form)
    other = contribution_form(
      name: "Verity Redline",
      main_url: "https://pactolane.example/verity",
      description: "Verity Redline is a redlining assistant for commercial contract negotiation teams."
    )
    second = UserContributionIntakeService.call(form: other)
    second.update!(status: "ready_for_review")
    CompanyProposalReturnService.call(
      proposal: second, admin_user: @admin,
      instructions: "Please supply the founding year.", fields: %w[founded_date]
    )

    answered = contribution_form(
      name: "Verity Redline",
      main_url: "https://pactolane.example/verity",
      description: "Verity Redline reviews and redlines commercial contracts for negotiation teams in house."
    )

    again = nil
    assert_no_difference "CompanyProposal.count" do
      again = UserContributionIntakeService.call(form: answered)
    end

    assert_equal second.id, again.id, "the second record reopens on its own identity"
    again.reload
    assert_equal "ready_for_review", again.status
    assert_nil again.agent_details["current_contributor_request"]
  end

  def contribution_form(name: "Pactolane", main_url: "https://www.pactolane.example", description: "Contract workflow software for in-house legal teams.", contact_email: "founder@pactolane.example")
    CompanyContributionForm.new(
      contact_email: contact_email,
      contact_name: "Ada Contributor",
      name: name,
      main_url: main_url,
      location: "Lyon, France",
      founded_date: "2024",
      category_id: categories(:one).id,
      description: description,
      status: "active",
      business_model_ids: [business_models(:one).id],
      target_client_ids: [target_clients(:one).id],
      tag_names: ["artificial intelligence"]
    )
  end
end
