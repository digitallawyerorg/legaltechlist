require "test_helper"

class CompanyAgentReviewServiceTest < ActiveSupport::TestCase
  test "creates proposal-only evidence and verifier output without changing company" do
    company = companies(:one)
    original_attributes = tracked_company_attributes(company)

    assert_difference "PipelineRun.count", 1 do
      @run = CompanyAgentReviewService.call(company: company, reviewer: "test@example.com", notes: "Agent proposal test")
    end

    assert_equal "succeeded", @run.status
    assert_equal "company_agent_review", @run.run_type
    assert_equal "CompanyEvidenceAgent+CompanyVerifierAgent+DescriptionDraftAgent+DescriptionCriticAgent+ReviewCoordinatorAgent", @run.agent_name
    assert_equal company.id, @run.details["company_id"]
    assert_equal "agent_proposal_no_public_writes", @run.details["mode"]
    assert_not_empty @run.details["evidence"]
    assert_equal true, @run.details["tool_results"]["domain_normalization"]["read_only"]
    assert_equal "example.com", @run.details["tool_results"]["domain_normalization"]["canonical_domain"]
    assert_not_empty @run.details["tool_results"]["stored_source_lookup"]["sources"]
    assert_includes @run.details["verification"].keys, "verdict"
    assert_includes @run.details["verification"].keys, "quality_score"
    assert_equal "deterministic_fallback", @run.details["description_draft"]["mode"]
    assert_equal "DescriptionDraftSchema", @run.details["description_draft"]["schema"]
    assert_equal DescriptionDraftSchema::SCHEMA_VERSION, @run.details["description_draft"]["schema_version"]
    assert_nil @run.details["description_draft"]["usage"]
    assert_nil @run.details["description_draft"]["estimated_cost_usd"]
    refute_match(/listed in TechIndex|included in TechIndex|TechIndex company/i, @run.details["description_draft"]["proposed_description"])
    assert_equal "DescriptionCriticSchema", @run.details["description_critic"]["schema"]
    assert_equal DescriptionCriticSchema::SCHEMA_VERSION, @run.details["description_critic"]["schema_version"]
    assert_includes %w[pass revise reject], @run.details["description_critic"]["verdict"]
    assert_equal "ReviewCoordinatorSchema", @run.details["review_coordinator"]["schema"]
    assert_equal ReviewCoordinatorSchema::SCHEMA_VERSION, @run.details["review_coordinator"]["schema_version"]
    assert_includes ReviewCoordinatorAgent::STATUSES, @run.details["review_coordinator"]["status"]
    assert_equal @run.details["description_draft"]["proposed_description"], @run.details["proposed_corrections"]["proposed_description"]
    assert_equal @run.details["description_critic"]["verdict"], @run.details["proposed_corrections"]["description_critic_verdict"]
    assert_equal @run.details["review_coordinator"]["status"], @run.details["proposed_corrections"]["coordinator_status"]
    assert_equal "needs_review", @run.details["proposed_corrections"]["quality_status"]
    assert_equal original_attributes, tracked_company_attributes(company.reload)
  end

  test "verifier flags weak descriptions as risks" do
    company = companies(:one)
    company.update_columns(description: "Short")

    run = CompanyAgentReviewService.call(company: company)

    assert_includes run.details["risks"], "Weak or short description."
    assert_equal "Draft a new neutral, source-backed TechIndex description before marking reviewed.", run.details["proposed_corrections"]["description_review"]
  end

  test "description draft avoids marketing terms and remains proposal only" do
    company = companies(:one)
    company.update_columns(description: "The best leading revolutionary solution for legal teams.")
    original_description = company.description

    run = CompanyAgentReviewService.call(company: company)
    proposed_description = run.details["proposed_corrections"]["proposed_description"]

    assert proposed_description.present?
    refute_match(/best|leading|revolutionary|cutting-edge|world-class|game-changing/i, proposed_description)
    assert_equal original_description, company.reload.description
  end

  test "description draft avoids directory meta language" do
    company = companies(:one)
    run = CompanyAgentReviewService.call(company: company)
    proposed_description = run.details["proposed_corrections"]["proposed_description"]

    assert proposed_description.present?
    refute_match(/listed in TechIndex|included in TechIndex|TechIndex company/i, proposed_description)
  end

  test "description draft avoids source meta language when facts are thin" do
    company = companies(:one)
    company.update_columns(category_id: nil, business_model_id: nil, target_client_id: nil)

    run = CompanyAgentReviewService.call(company: company)
    proposed_description = run.details["proposed_corrections"]["proposed_description"]

    assert proposed_description.present?
    refute_match(/available records|directory metadata|stored profiles|associated social profiles|primary web presence|current TechIndex record|through its .* domain/i, proposed_description)
  end

  test "description critic flags directory metadata phrasing" do
    company = companies(:one)
    evidence_payload = CompanyEvidenceAgent.call(company)
    verification_payload = CompanyVerifierAgent.call(company, evidence_payload: evidence_payload)
    description_payload = {
      "proposed_description" => "#{company.name} supports litigation teams based on available directory metadata and associated social profiles.",
      "rationale" => "Test weak phrasing.",
      "warnings" => []
    }

    critique = DescriptionCriticAgent.call(company, evidence_payload: evidence_payload, verification_payload: verification_payload, description_payload: description_payload)

    assert_equal "revise", critique["verdict"]
    assert_includes critique["issues"], "Description uses directory-meta phrasing rather than describing the company."
    assert_includes critique["issues"], "Description references weak or indirect evidence instead of company facts."
    assert_equal company.description, company.reload.description
  end

  test "description critic flags source meta phrasing" do
    company = companies(:one)
    evidence_payload = CompanyEvidenceAgent.call(company)
    verification_payload = CompanyVerifierAgent.call(company, evidence_payload: evidence_payload)
    description_payload = {
      "proposed_description" => "#{company.name} provides legal technology support through its example.com domain and primary web presence.",
      "rationale" => "Test source meta phrasing.",
      "warnings" => []
    }

    critique = DescriptionCriticAgent.call(company, evidence_payload: evidence_payload, verification_payload: verification_payload, description_payload: description_payload)

    assert_equal "revise", critique["verdict"]
    assert_includes critique["issues"], "Description uses directory-meta phrasing rather than describing the company."
    assert_includes critique["issues"], "Description references weak or indirect evidence instead of company facts."
    assert_equal company.description, company.reload.description
  end

  test "review coordinator guardrails prevent ready status when critic requires revision" do
    company = companies(:one)
    evidence_payload = CompanyEvidenceAgent.call(company)
    verification_payload = CompanyVerifierAgent.call(company, evidence_payload: evidence_payload)
    description_payload = { "proposed_description" => "A neutral draft.", "confidence" => "medium", "warnings" => [] }
    critic_payload = {
      "verdict" => "revise",
      "issues" => ["Needs stronger evidence."],
      "rationale" => "Critic requires revision.",
      "suggested_revision" => "",
      "confidence" => "high"
    }

    coordination = ReviewCoordinatorAgent.call(company, evidence_payload: evidence_payload, verification_payload: verification_payload, description_payload: description_payload, critic_payload: critic_payload)

    assert_includes %w[needs_description_revision needs_more_evidence possible_duplicate do_not_publish], coordination["status"]
    assert_includes coordination["guardrails"].map { |guardrail| guardrail["status"] }, "needs_description_revision"
    assert_equal company.description, company.reload.description
  end

  private

  def tracked_company_attributes(company)
    company.attributes.slice("name", "description", "main_url", "visible", "quality_status", "verification_verdict", "quality_score", "canonical_domain", "fingerprint")
  end
end
