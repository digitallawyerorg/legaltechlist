require "test_helper"

class TagSuggestionServiceTest < ActiveSupport::TestCase
  test "uses keyword backfill before llm" do
    company = companies(:one)
    company.tags.destroy_all
    company.update_columns(human_reviewed_at: nil, description: "Cloud SaaS platform for contract management and compliance.")

    result = TagSuggestionService.call(company: company, dry_run: true)

    assert_equal "would_tag", result["action"]
    assert_includes result["suggested_tags"], "saas"
  end

  test "skips already tagged companies" do
    company = companies(:one)
    company.tags << Tag.create!(name: "saas") unless company.tags.exists?

    result = TagSuggestionService.call(company: company, dry_run: true)

    assert_equal "skipped_already_tagged", result["action"]
  end
end
