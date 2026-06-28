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

  test "apply mode preserves discoverable canonical tags" do
    company = companies(:one)
    discoverable_tag = Tag.create!(name: "access to justice")
    redundant_tag = Tag.create!(name: "saas")
    company.tags = [discoverable_tag, redundant_tag]

    TagCleanupService.call(dry_run: false)

    names = company.reload.tags.pluck(:name)
    assert_includes names, "access to justice"
    refute_includes names, "saas"
  end
end
