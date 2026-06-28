require "test_helper"

class TagNormalizationServiceTest < ActiveSupport::TestCase
  setup do
    TagNormalizationService.instance_variable_set(:@alias_map, nil)
  end

  test "ai_related_tag_ids include canonical and alias tags" do
    ai = tags(:one)
    ml = tags(:two)

    ids = TagNormalizationService.ai_related_tag_ids

    assert_includes ids, ai.id
    assert_includes ids, ml.id
  end

  test "canonical_name maps production duplicate clusters" do
    assert_equal "compliance", TagNormalizationService.canonical_name("Regulatory Compliance")
    assert_equal "intellectual property", TagNormalizationService.canonical_name("IP Management")
    assert_equal "e-discovery", TagNormalizationService.canonical_name("Litigation Support")
    assert_equal "marketplace", TagNormalizationService.canonical_name("Legal Marketplace")
    assert_equal "e-signature", TagNormalizationService.canonical_name("Electronic Signature")
    assert_equal "saas", TagNormalizationService.canonical_name("Software as a Service")
    assert_equal "law firms", TagNormalizationService.canonical_name("Law Firm Software")
    assert_equal "legal tech", TagNormalizationService.canonical_name("legaltech")
  end

  test "merge_duplicate_tags merges alias tag records" do
    keeper = Tag.create!(name: "compliance")
    duplicate = Tag.create!(name: "regulatory compliance")
    company = companies(:one)
    company.tags << duplicate

    counts = TagNormalizationService.merge_duplicate_tags!(dry_run: false)

    assert counts[:merged].positive?
    assert_includes company.reload.tags.pluck(:name), "compliance"
    assert_not Tag.exists?(duplicate.id)
  end
end
