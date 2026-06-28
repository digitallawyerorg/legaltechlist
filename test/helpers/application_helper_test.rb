require 'test_helper'

class ApplicationHelperTest < ActionView::TestCase
  PRIMARY_CATEGORY_NAMES = [
    "Document Management and Automation",
    "Compliance & Risk",
    "Practice Management",
    "Marketplace and ALSPs",
    "Litigation & Dispute Resolution",
    "Knowledge & Research",
    "Contract Management",
    "IP Management",
    "Analytics & Insights",
    "eDiscovery & Investigations",
    "Legal Operations / ELM",
    "Access to Justice & Public Sector"
  ].freeze

  test "category_icon assigns distinct icons for primary categories" do
    icons = PRIMARY_CATEGORY_NAMES.map { |name| category_icon(name) }

    assert_equal icons.uniq.size, icons.size
    assert_equal "fa fa-calendar-check", category_icon("Practice Management")
    assert_equal "fa fa-magnifying-glass", category_icon("eDiscovery & Investigations")
    assert_equal "fa fa-landmark", category_icon("Access to Justice & Public Sector")
  end
end
