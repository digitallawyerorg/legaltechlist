require "test_helper"

# Covers duplicate resolution: comparing a flagged proposal against the record it
# matched, merging only the gaps it can actually support, and the confidence tiering
# that stops a name coincidence being asserted as a duplicate.
class DuplicateResolutionTest < ActiveSupport::TestCase
  setup do
    @admin = admin_users(:one)
    @company = companies(:one)
    @company.update!(
      name: "Pactolane",
      main_url: "https://www.pactolane.com",
      description: "Pactolane builds contract lifecycle management software for legal and procurement teams.",
      location: "Lyon, France"
    )
    @company.update_columns(
      canonical_domain: "pactolane.com", quality_status: nil, founded_date: nil,
      linkedin_url: nil, crunchbase_url: nil, fingerprint: @company.calculated_fingerprint
    )
  end

  def proposal_for(changes, evidence: true)
    full = {
      "name" => "Pactolane",
      "main_url" => "https://www.pactolane.com",
      "category_id" => categories(:one).id,
      "business_model_id" => business_models(:one).id,
      "business_model_ids" => [business_models(:one).id],
      "target_client_id" => target_clients(:one).id,
      "target_client_ids" => [target_clients(:one).id]
    }.merge(changes)

    CompanyProposal.create!(
      status: "ready_for_review", proposal_type: "user_contribution", source: "user_contribution",
      source_identifier: SecureRandom.uuid, source_payload: {},
      proposed_changes: full, final_changes: full, duplicate_signals: {},
      enriched_at: Time.current,
      agent_details: evidence ? researched_agent_details(url: "https://www.pactolane.com") : {}
    )
  end

  # ---- comparison ---------------------------------------------------------

  test "comparison reports identical, missing and conflicting fields separately" do
    proposal = proposal_for({      "description" => "Pactolane builds contract lifecycle management software for legal and procurement teams.",
      "location" => "Paris, France",
      "founded_date" => "2021"})
    rows = DuplicateComparisonService.call(proposal: proposal, company: @company)["rows"].index_by { |r| r["key"] }

    assert_equal "identical", rows["description"]["verdict"]
    assert_equal "conflict", rows["location"]["verdict"], "both hold a location and they differ"
    assert_equal "only_here", rows["founded_date"]["verdict"], "the index has no founding year"
  end

  test "only gaps on non-identity fields are offered for merge" do
    proposal = proposal_for({"founded_date" => "2021", "linkedin_url" => "https://linkedin.com/company/pactolane", "name" => "Pactolane Renamed"})
    comparison = DuplicateComparisonService.call(proposal: proposal, company: @company)

    assert_includes comparison["mergeable_fields"], "founded_date"
    assert_includes comparison["mergeable_fields"], "linkedin_url"
    refute_includes comparison["mergeable_fields"], "name", "renaming an entry is not a gap fill"
    assert_equal "merge_then_reject", comparison["recommendation"]["action"]
  end

  test "an unverified proposal offers nothing to merge and is recommended for rejection" do
    proposal = proposal_for({ "founded_date" => "2021" }, evidence: false)
    comparison = DuplicateComparisonService.call(proposal: proposal, company: @company)

    assert_empty comparison["mergeable_fields"]
    assert_equal "reject_duplicate", comparison["recommendation"]["action"]
    assert_match(/independently retrieved/i, comparison["recommendation"]["summary"])
  end

  test "conflicting values with nothing to merge are escalated rather than resolved" do
    proposal = proposal_for({"location" => "Paris, France", "description" => "A different description of the same company that is long enough to count."})
    comparison = DuplicateComparisonService.call(proposal: proposal, company: @company)

    assert_empty comparison["mergeable_fields"]
    assert_equal "needs_human", comparison["recommendation"]["action"]
    assert_includes comparison["conflicts"], "location"
  end

  # ---- merge --------------------------------------------------------------

  test "merging fills gaps, records provenance and rejects the proposal in favour of the kept record" do
    proposal = proposal_for({"founded_date" => "2021", "location" => "Paris, France"})

    assert_difference "PipelineRun.count", 1 do
      DuplicateMergeService.call(proposal: proposal, company: @company, fields: %w[founded_date], admin_user: @admin)
    end

    @company.reload
    proposal.reload
    assert_equal "2021", @company.founded_date, "the gap was filled"
    assert_equal "Lyon, France", @company.location,
                 "a field the reviewer did not name is left alone, however much the proposal disagrees with it"
    assert_equal "rejected", proposal.status
    assert_equal @company.id, proposal.agent_details.dig("canonical_record", "company_id")
    assert_equal ["founded_date"], proposal.agent_details.dig("canonical_record", "merged_fields")

    run = PipelineRun.order(:id).last
    assert_equal "duplicate_merge", run.run_type
    assert_equal "2021", run.details.dig("applied_changes", "founded_date", "to")
    assert_nil run.details.dig("applied_changes", "founded_date", "from")
    assert run.details.dig("applied_changes", "founded_date", "sources").any?, "the merge records what supported the value"
  end

  test "merging refuses a field that is not the reviewer's to change" do
    proposal = proposal_for({"main_url" => "https://pactolane.io"})

    error = assert_raises(ArgumentError) do
      DuplicateMergeService.call(proposal: proposal, company: @company, fields: %w[main_url], admin_user: @admin)
    end
    assert_match(/None of the selected fields can be merged/, error.message)
    assert_equal "https://www.pactolane.com", @company.reload.main_url,
                 "identity is a rename decision, not a duplicate resolution"
  end

  test "merging refuses everything from a proposal nothing was retrieved for" do
    proposal = proposal_for({"location" => "Paris, France", "founded_date" => "2021"}, evidence: false)

    assert_raises(ArgumentError) do
      DuplicateMergeService.call(proposal: proposal, company: @company, fields: %w[location founded_date], admin_user: @admin)
    end
    assert_equal "Lyon, France", @company.reload.location
    assert_nil @company.founded_date
  end

  # ---- confidence tiering -------------------------------------------------

  test "a name match with nothing else agreeing is possible, not confirmed" do
    @company.update_columns(canonical_domain: "somethingelse.example", main_url: "https://somethingelse.example")
    signals = proposal_for({"main_url" => "https://pactolane.io"}).current_duplicate_signals

    assert signals["blocking"], "a human still has to resolve it"
    assert_equal ProposalDuplicateDetectorService::CONFIDENCE_POSSIBLE, signals["confidence"]
    assert_match(/Possibly the same company/, signals["recommended_action"])
  end

  test "a shared profile raises a name match to confirmed" do
    @company.update_columns(canonical_domain: "somethingelse.example", main_url: "https://somethingelse.example",
                            linkedin_url: "https://www.linkedin.com/company/pactolane/")
    signals = proposal_for({"main_url" => "https://pactolane.io", "linkedin_url" => "https://linkedin.com/company/pactolane"}).current_duplicate_signals

    assert_equal ProposalDuplicateDetectorService::CONFIDENCE_CONFIRMED, signals["confidence"]
    assert_includes signals["name_matches"].first["shared_profiles"], "linkedin"
  end

  # Hafez's case: one company, two products. Same website, different product names.
  test "a shared website with a different name is flagged as possibly a sibling product" do
    signals = proposal_for({"name" => "Pactolane Signature Vault"}).current_duplicate_signals

    assert_equal ProposalDuplicateDetectorService::CONFIDENCE_POSSIBLE, signals["confidence"]
    assert_match(/different product from the same company/, signals["recommended_action"])
  end
end
