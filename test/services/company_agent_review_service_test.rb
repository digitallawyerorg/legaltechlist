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
    assert_equal "CompanyEvidenceAgent+CompanyVerifierAgent+DescriptionDraftAgent", @run.agent_name
    assert_equal company.id, @run.details["company_id"]
    assert_equal "agent_proposal_no_public_writes", @run.details["mode"]
    assert_not_empty @run.details["evidence"]
    assert_includes @run.details["verification"].keys, "verdict"
    assert_includes @run.details["verification"].keys, "quality_score"
    assert_equal "deterministic_fallback", @run.details["description_draft"]["mode"]
    assert_equal "DescriptionDraftSchema", @run.details["description_draft"]["schema"]
    assert_equal DescriptionDraftSchema::SCHEMA_VERSION, @run.details["description_draft"]["schema_version"]
    assert_nil @run.details["description_draft"]["usage"]
    assert_nil @run.details["description_draft"]["estimated_cost_usd"]
    refute_match(/listed in TechIndex|included in TechIndex|TechIndex company/i, @run.details["description_draft"]["proposed_description"])
    assert_equal @run.details["description_draft"]["proposed_description"], @run.details["proposed_corrections"]["proposed_description"]
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

  private

  def tracked_company_attributes(company)
    company.attributes.slice("name", "description", "main_url", "visible", "quality_status", "verification_verdict", "quality_score", "canonical_domain", "fingerprint")
  end
end
