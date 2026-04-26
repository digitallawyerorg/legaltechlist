require 'test_helper'

class CompanyTest < ActiveSupport::TestCase
  test "publicly_visible matches visible companies" do
    hidden = companies(:one).dup
    hidden.name = "Hidden Company"
    hidden.visible = false
    hidden.save!

    assert_includes Company.publicly_visible, companies(:one)
    assert_not_includes Company.publicly_visible, hidden
  end

  test "canonical domain normalizes website URLs" do
    assert_equal "example.com", Company.canonical_domain_for("https://www.example.com/path?ref=1")
    assert_equal "example.com", Company.canonical_domain_for("example.com")
    assert_nil Company.canonical_domain_for("Unknown")
  end

  test "fingerprint uses normalized name and canonical domain" do
    first = Company.fingerprint_for("Example Legal  Inc.", "https://www.example.com")
    second = Company.fingerprint_for("example legal inc", "http://example.com/about")

    assert_equal first, second
  end
end
