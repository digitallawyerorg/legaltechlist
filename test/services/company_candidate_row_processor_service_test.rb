require "test_helper"
require "minitest/mock"

class CompanyCandidateRowProcessorServiceTest < ActiveSupport::TestCase
  test "discovery candidates arrive pre-classified from search taxonomy and cited year" do
    admin = AdminUser.create!(email: "rp-#{SecureRandom.hex(3)}@example.com", password: "password123", password_confirmation: "password123")
    candidate = {
      "name" => "Prefill Legal Co",
      "website" => "https://prefill-legal.example",
      "canonical_domain" => "prefill-legal.example",
      "location" => "Paris, France",
      "founded_date" => "2019",
      "category_name" => categories(:one).name,
      "business_model_names" => [business_models(:one).name],
      "target_client_names" => [target_clients(:one).name],
      "founded_year_source" => "https://linkedin.example/company/prefill",
      "status" => "absent_candidate"
    }

    CompanyCandidateRowProcessorService.call(
      candidate: candidate,
      index: 0,
      admin_user: admin,
      source: "llm_discovery",
      proposal_type: "discovery_candidate",
      source_label: "LLM Discovery",
      skip_auto_draft: true
    )

    proposal = CompanyProposal.find_by(source: "llm_discovery", source_identifier: "prefill-legal.example")
    assert proposal, "expected a discovery proposal to be created"
    assert_equal categories(:one).id, proposal.final_changes["category_id"]
    assert_equal [business_models(:one).id], proposal.final_changes["business_model_ids"]
    assert_equal [target_clients(:one).id], proposal.final_changes["target_client_ids"]
    assert proposal.agent_details.dig("taxonomy_suggestion", "accepted"), "taxonomy should be accepted when fully mapped"
    assert_equal "https://linkedin.example/company/prefill", proposal.agent_details.dig("founded_date_source", "source_url")
  end

  test "discovery prefill maps a secondary category and tags" do
    admin = AdminUser.create!(email: "rp-#{SecureRandom.hex(3)}@example.com", password: "password123", password_confirmation: "password123")
    tag = TagTaxonomyService.discoverable_canonical_names.first
    candidate = {
      "name" => "Tagged Legal Co",
      "website" => "https://tagged-legal.example",
      "canonical_domain" => "tagged-legal.example",
      "category_name" => categories(:one).name,
      "secondary_category_name" => categories(:two).name,
      "business_model_names" => [business_models(:one).name],
      "target_client_names" => [target_clients(:one).name],
      "tag_names" => [tag],
      "status" => "absent_candidate"
    }

    CompanyCandidateRowProcessorService.call(
      candidate: candidate,
      index: 0,
      admin_user: admin,
      source: "llm_discovery",
      proposal_type: "discovery_candidate",
      source_label: "LLM Discovery",
      skip_auto_draft: true
    )

    proposal = CompanyProposal.find_by(source: "llm_discovery", source_identifier: "tagged-legal.example")
    assert proposal, "expected a discovery proposal to be created"
    assert_equal categories(:two).id, proposal.final_changes["secondary_category_id"]
    assert_includes proposal.final_changes["all_tags"].to_s, tag
    assert proposal.agent_details.dig("taxonomy_suggestion", "tags", "accepted"), "tags should be recorded as accepted"
  end

  test "a complete critic-passing discovery prefill is marked enriched with a quality report" do
    admin = AdminUser.create!(email: "rp-#{SecureRandom.hex(3)}@example.com", password: "password123", password_confirmation: "password123")
    drafted = "Enriched Legal develops contract review and clause extraction software for corporate legal teams to analyze agreements and monitor obligations across large document collections."
    candidate = {
      "name" => "Enriched Legal Co",
      "website" => "https://enriched-legal.example",
      "canonical_domain" => "enriched-legal.example",
      "location" => "London, United Kingdom",
      "founded_date" => "2020",
      "category_name" => categories(:one).name,
      "business_model_names" => [business_models(:one).name],
      "target_client_names" => [target_clients(:one).name],
      "discovery_description" => drafted,
      "status" => "absent_candidate"
    }

    CompanyCandidateRowProcessorService.call(
      candidate: candidate,
      index: 0,
      admin_user: admin,
      source: "llm_discovery",
      proposal_type: "discovery_candidate",
      source_label: "LLM Discovery",
      skip_auto_draft: true
    )

    proposal = CompanyProposal.find_by(source: "llm_discovery", source_identifier: "enriched-legal.example")
    assert proposal, "expected a discovery proposal to be created"
    assert proposal.enriched_at.present?, "a complete prefill should be marked enriched to skip the 3-call enrichment"
    assert_equal "ready_for_review", proposal.status
    assert proposal.agent_details["quality"].present?, "a quality report should be stamped for observability"
  end

  test "does not overwrite existing taxonomy on re-discovery" do
    admin = AdminUser.create!(email: "rp-#{SecureRandom.hex(3)}@example.com", password: "password123", password_confirmation: "password123")
    existing = CompanyProposal.create!(
      source: "llm_discovery",
      source_identifier: "keep-legal.example",
      proposal_type: "discovery_candidate",
      status: "ready_for_review",
      admin_user: admin,
      final_changes: { "name" => "Keep Legal", "category_id" => categories(:two).id },
      agent_details: { "taxonomy_suggestion" => { "accepted" => true, "mode" => "curator" } }
    )

    candidate = {
      "name" => "Keep Legal",
      "website" => "https://keep-legal.example",
      "canonical_domain" => "keep-legal.example",
      "category_name" => categories(:one).name,
      "business_model_names" => [business_models(:one).name],
      "target_client_names" => [target_clients(:one).name],
      "status" => "absent_candidate"
    }

    CompanyCandidateRowProcessorService.call(
      candidate: candidate,
      index: 0,
      admin_user: admin,
      source: "llm_discovery",
      proposal_type: "discovery_candidate",
      source_label: "LLM Discovery",
      skip_auto_draft: true
    )

    existing.reload
    assert_equal "curator", existing.agent_details.dig("taxonomy_suggestion", "mode")
    assert_equal categories(:two).id, existing.final_changes["category_id"]
  end

  test "clean drafted description is promoted at discovery time and skips enrichment" do
    admin = AdminUser.create!(email: "rp-#{SecureRandom.hex(3)}@example.com", password: "password123", password_confirmation: "password123")
    drafted = "Acme Legal develops contract review and clause extraction software for corporate legal teams to analyze agreements and monitor obligations across large document collections."
    candidate = {
      "name" => "Acme Legal Draft",
      "website" => "https://acme-draft.example",
      "canonical_domain" => "acme-draft.example",
      "location" => "London, United Kingdom",
      "founded_date" => "2020",
      "category_name" => categories(:one).name,
      "business_model_names" => [business_models(:one).name],
      "target_client_names" => [target_clients(:one).name],
      "discovery_description" => drafted,
      "status" => "absent_candidate"
    }

    CompanyProposalEnrichmentService.stub(:call, ->(*) { raise "enrichment should not run for a fully-drafted discovery candidate" }) do
      CompanyCandidateRowProcessorService.call(
        candidate: candidate,
        index: 0,
        admin_user: admin,
        source: "llm_discovery",
        proposal_type: "discovery_candidate",
        source_label: "LLM Discovery"
      )
    end

    proposal = CompanyProposal.find_by(source: "llm_discovery", source_identifier: "acme-draft.example")
    assert proposal, "expected a discovery proposal to be created"
    assert_equal drafted, proposal.final_changes["description"]
    assert_equal "pass", proposal.agent_details.dig("description_critic", "verdict")

    # The drafted description clears the critic and every required field is filled, but
    # nothing has been retrieved for this candidate, so it is complete rather than
    # verified and cannot publish on that basis alone.
    report = CompanyProposalQualityService.call(proposal)
    assert_empty report["missing_publish_blocking_fields"]
    assert_equal "unverified", report["verification_state"]
    refute report["publish_ready"]
  end

  # The unattended disposition. On this path a blocking duplicate is resolved by
  # REJECTING the candidate and merging its blank fields into the matched row, with no
  # human anywhere in the loop - the shape that auto-rejected Notaron 4167 in the same
  # second it arrived, admin_user null. Advisory evidence may not buy that disposition,
  # and it may not buy the opposite one either: the row is neither rejected nor drafted,
  # it stops for a human with the comparison named on it.
  test "an advisory duplicate is neither auto-rejected nor auto-drafted" do
    admin = AdminUser.create!(email: "rp-#{SecureRandom.hex(3)}@example.com", password: "password123", password_confirmation: "password123")
    company = companies(:one)
    company.update!(name: "Pactolane", main_url: "https://www.pactolane.com")
    company.update_columns(canonical_domain: "pactolane.com", quality_status: nil, visible: true)

    result = CompanyCandidateRowProcessorService.call(
      candidate: {
        "name" => "Pactolane Technologies",
        "website" => "https://pactolane-clm.example",
        "canonical_domain" => "pactolane-clm.example",
        "status" => "absent_candidate"
      },
      index: 0,
      admin_user: admin,
      source: "llm_discovery",
      proposal_type: "discovery_candidate",
      source_label: "LLM Discovery"
    )

    assert_equal "needs_review", result["action"]
    proposal = CompanyProposal.find(result["proposal_id"])
    refute_equal "rejected", proposal.status, "a single loose key may not dispose of a record unattended"
    assert_nil proposal.company_id, "and it may not mint a second row either"
    assert proposal.duplicate_advisory?
    refute proposal.duplicate_blocking?
  end

  # The blocking half, unchanged: strong corroborated evidence still resolves against
  # the matched row on this path, because duplicate detection is still a mandatory gate.
  test "a blocking duplicate is still resolved against the matched row" do
    admin = AdminUser.create!(email: "rp-#{SecureRandom.hex(3)}@example.com", password: "password123", password_confirmation: "password123")
    company = companies(:one)
    company.update!(name: "Pactolane", main_url: "https://www.pactolane.com")
    company.update_columns(canonical_domain: "pactolane.com", quality_status: nil, visible: true)

    result = CompanyCandidateRowProcessorService.call(
      candidate: {
        "name" => "Pactolane",
        "website" => "https://www.pactolane.com",
        "canonical_domain" => "pactolane.com",
        "status" => "absent_candidate"
      },
      index: 0,
      admin_user: admin,
      source: "llm_discovery",
      proposal_type: "discovery_candidate",
      source_label: "LLM Discovery"
    )

    assert_includes %w[duplicate_merged duplicate_rejected], result["action"]
    assert_equal "rejected", CompanyProposal.find(result["proposal_id"]).status
  end

  test "weak drafted description is left for enrichment" do
    admin = AdminUser.create!(email: "rp-#{SecureRandom.hex(3)}@example.com", password: "password123", password_confirmation: "password123")
    candidate = {
      "name" => "Weak Draft Legal",
      "website" => "https://weak-draft.example",
      "canonical_domain" => "weak-draft.example",
      "category_name" => categories(:one).name,
      "business_model_names" => [business_models(:one).name],
      "target_client_names" => [target_clients(:one).name],
      "discovery_description" => "Legal tech company.",
      "status" => "absent_candidate"
    }

    CompanyCandidateRowProcessorService.call(
      candidate: candidate,
      index: 0,
      admin_user: admin,
      source: "llm_discovery",
      proposal_type: "discovery_candidate",
      source_label: "LLM Discovery",
      skip_auto_draft: true
    )

    proposal = CompanyProposal.find_by(source: "llm_discovery", source_identifier: "weak-draft.example")
    assert proposal, "expected a discovery proposal to be created"
    assert proposal.final_changes["description"].blank?, "weak draft should not be promoted"
    assert proposal.agent_details["description_critic"].blank?, "no critic verdict should be recorded for a rejected draft"
  end
end
