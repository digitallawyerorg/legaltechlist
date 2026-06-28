require "test_helper"

class AiCapabilityDerivationServiceTest < ActiveSupport::TestCase
  test "derives none when no tags" do
    company = companies(:one)
    company.tags.destroy_all

    assert_equal "none", AiCapabilityDerivationService.call(company: company)
  end

  test "derives ml from machine learning tag" do
    assert_equal "ml", AiCapabilityDerivationService.derive_from_tag_names(["machine learning"])
  end

  test "derives genai from generative ai tag" do
    assert_equal "genai", AiCapabilityDerivationService.derive_from_tag_names(["generative ai"])
  end

  test "derives agentic from agentic tag" do
    assert_equal "agentic", AiCapabilityDerivationService.derive_from_tag_names(["agentic"])
  end

  test "agentic wins over genai" do
    assert_equal "agentic", AiCapabilityDerivationService.derive_from_tag_names(["generative ai", "agentic"])
  end
end
