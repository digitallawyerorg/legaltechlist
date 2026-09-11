require "test_helper"

# What a reviewer can do with a duplicate after they have checked the sources.
#
# The comparison would tell them the two records disagreed on location — "United
# States" against "Las Vegas, NV, USA" — invite them to verify, and then offer only
# "keep the existing record and reject the proposal". The verification had nowhere to
# go and the vaguer value stayed.
class DuplicateResolutionChoicesTest < ActiveSupport::TestCase
  DESCRIPTION = "Trusted Directive builds advance-directive and healthcare proxy tooling for estate planning practices.".freeze
  PROPOSAL_DESCRIPTION = "Trusted Directive builds advance-directive registration and healthcare proxy workflows for estate planning attorneys in Nevada.".freeze

  setup do
    @admin = admin_users(:one)
    @company = companies(:one)
    @company.update!(name: "Trusted Directive", main_url: "https://trusteddirective.example",
                     description: DESCRIPTION, location: "United States", founded_date: "2019")
    @company.update_columns(linkedin_url: "https://linkedin.com/company/trusted-directive")
  end

  def duplicate_proposal(changes = {})
    final = { "name" => "Trusted Directive", "main_url" => "https://trusteddirective.example",
              "description" => PROPOSAL_DESCRIPTION, "location" => "Las Vegas, NV, USA" }.merge(changes)
    CompanyProposal.create!(
      status: "ready_for_review", proposal_type: "user_contribution", source: "user_contribution",
      source_identifier: SecureRandom.uuid, source_payload: {}, duplicate_signals: {},
      proposed_changes: final, final_changes: final, enriched_at: Time.current,
      agent_details: researched_agent_details(url: "https://trusteddirective.example")
    )
  end

  def comparison(proposal) = DuplicateComparisonService.call(proposal: proposal, company: @company.reload)

  # ---- what the comparison now offers -------------------------------------

  test "a field both records hold, differently, is offered as an explicit choice" do
    rows = comparison(duplicate_proposal)["rows"].index_by { |row| row["key"] }

    assert_equal "conflict", rows["location"]["verdict"]
    assert rows["location"]["overridable"], "the reviewer has to be able to record what they verified"
    refute rows["location"]["mergeable"], "it is not a gap fill: the index already holds a value"
  end

  test "identity is never offered as a duplicate-resolution choice" do
    rows = comparison(duplicate_proposal("main_url" => "https://trusted-directive.example"))["rows"].index_by { |row| row["key"] }

    assert_equal "conflict", rows["main_url"]["verdict"]
    refute rows["main_url"]["overridable"], "changing what an entry is, is a rename — not a duplicate resolution"
  end

  test "an unverified proposal cannot change a live entry at all" do
    bare = duplicate_proposal
    bare.update!(agent_details: {}, enriched_at: nil)

    result = comparison(bare)
    assert_empty result["overridable_fields"]
    assert_empty result["mergeable_fields"]
  end

  # ---- applying the reviewer's choices ------------------------------------

  test "only the fields the reviewer chose are written, and the rest are left alone" do
    proposal = duplicate_proposal
    previous_description = @company.description

    result = DuplicateMergeService.call(proposal: proposal, company: @company, fields: %w[location], admin_user: @admin)
    @company.reload

    assert_equal "Las Vegas, NV, USA", @company.location
    assert_equal previous_description, @company.description, "a field not chosen is not touched"
    assert_equal "2019", @company.founded_date
    assert_equal "override", result["applied"]["location"]["kind"]
    assert_equal "United States", result["applied"]["location"]["from"]
  end

  test "fields are resolved independently of one another" do
    proposal = duplicate_proposal

    DuplicateMergeService.call(proposal: proposal, company: @company, fields: %w[location description], admin_user: @admin)
    @company.reload

    assert_equal "Las Vegas, NV, USA", @company.location
    assert_equal PROPOSAL_DESCRIPTION, @company.description
    assert_equal "https://linkedin.com/company/trusted-directive", @company.linkedin_url, "untouched values survive"
  end

  test "a field the reviewer did not choose cannot be written by asking for it anyway" do
    proposal = duplicate_proposal("main_url" => "https://trusted-directive.example")

    assert_raises(ArgumentError) do
      DuplicateMergeService.call(proposal: proposal, company: @company, fields: %w[main_url], admin_user: @admin)
    end
    assert_equal "https://trusteddirective.example", @company.reload.main_url
  end

  test "a blank proposal value never erases a populated field" do
    proposal = duplicate_proposal("location" => "")

    assert_raises(ArgumentError) do
      DuplicateMergeService.call(proposal: proposal, company: @company, fields: %w[location], admin_user: @admin)
    end
    assert_equal "United States", @company.reload.location
  end

  # ---- what is left behind ------------------------------------------------

  test "the duplicate is resolved, and what moved is recorded with both values" do
    proposal = duplicate_proposal

    DuplicateMergeService.call(proposal: proposal, company: @company, fields: %w[location], admin_user: @admin)
    proposal.reload

    assert_equal "rejected", proposal.status
    assert_equal @company.id, proposal.agent_details.dig("canonical_record", "company_id")
    assert_equal %w[location], proposal.agent_details.dig("canonical_record", "overridden_fields")
    refute_includes CompanyProposal.pending_review, proposal

    run = PipelineRun.where(run_type: "duplicate_merge").order(:created_at).last
    assert_equal @admin.email, run.details["merged_by"]
    assert_equal "United States", run.details.dig("applied_changes", "location", "from")
    assert_equal "Las Vegas, NV, USA", run.details.dig("applied_changes", "location", "to")
  end

  # Rejecting first would discard the evidence for a write that then failed.
  test "the duplicate is not rejected when the canonical record refuses the change" do
    proposal = duplicate_proposal

    assert_raises(ActiveRecord::RecordInvalid) do
      @company.stub(:save!, ->(*) { raise ActiveRecord::RecordInvalid, @company }) do
        DuplicateMergeService.call(proposal: proposal, company: @company, fields: %w[location], admin_user: @admin)
      end
    end

    assert_equal "ready_for_review", proposal.reload.status, "the proposal stays open for another attempt"
    assert_equal "United States", @company.reload.location
  end
end
