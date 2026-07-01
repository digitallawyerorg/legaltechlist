# frozen_string_literal: true

require "test_helper"

class SlugsRakeTest < ActiveSupport::TestCase
  test "assign_unique_slugs dry run leaves records unchanged" do
    company = companies(:one)
    original_slug = company.slug
    company.update_column(:slug, nil)

    updates = Company.assign_unique_slugs!(scope: Company.where(id: company.id), slug_source: :name, dry_run: true)

    assert_equal 1, updates.size
    assert_nil company.reload.slug
  ensure
    company.update_column(:slug, original_slug)
  end
end
