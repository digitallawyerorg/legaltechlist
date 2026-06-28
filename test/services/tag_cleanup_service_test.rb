require "test_helper"

class TagCleanupServiceTest < ActiveSupport::TestCase
  test "dry run reports redundant taggings without deleting" do
    company = companies(:one)
    redundant_tag = Tag.create!(name: "saas")
    company.tags << redundant_tag

    counts = TagCleanupService.call(dry_run: true)

    assert counts[:redundant_taggings_removed].positive?
    assert company.reload.tags.include?(redundant_tag)
  end

  test "apply mode removes redundant taggings" do
    company = companies(:one)
    redundant_tag = Tag.create!(name: "saas")
    useful_tag = Tag.create!(name: "generative ai")
    company.tags = [redundant_tag, useful_tag]

    TagCleanupService.call(dry_run: false)

    names = company.reload.tags.pluck(:name)
    refute_includes names, "saas"
    assert_includes names, "generative ai"
  end
end
