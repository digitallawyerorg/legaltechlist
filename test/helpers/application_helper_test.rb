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

  # The duplicate panel printed the matched record's stored canonical_domain beside
  # "matched on <key>", which on a rebranded entry is the domain it used to carry.
  # The basis names the value the key was compared on.
  test "admin_duplicate_match_basis names the value the match fired on" do
    match = {
      "match_type" => "exact_domain", "match_types" => %w[exact_domain exact_name],
      "matched_value" => "apertera.com", "canonical_domain" => "alexatranslations.com"
    }

    assert_equal "matched on exact domain (apertera.com) and exact name", admin_duplicate_match_basis(match)
  end

  test "admin_duplicate_match_basis falls back to the single strongest key" do
    assert_equal "matched on core name (apertera)",
                 admin_duplicate_match_basis("match_type" => "core_name", "matched_value" => "apertera")
    assert_equal "", admin_duplicate_match_basis({})
  end

  test "admin_duplicate_listed_address only speaks when the entry is listed elsewhere" do
    stale = { "matched_value" => "apertera.com", "canonical_domain" => "alexatranslations.com" }
    same = { "matched_value" => "apertera.com", "canonical_domain" => "apertera.com" }

    assert_equal "entry is listed at alexatranslations.com", admin_duplicate_listed_address(stale)
    assert_nil admin_duplicate_listed_address(same), "no point repeating the matched domain"
    assert_nil admin_duplicate_listed_address({})
  end
end
