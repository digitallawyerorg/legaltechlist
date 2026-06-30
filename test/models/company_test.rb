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

  test "status is normalized before validation" do
    company = companies(:one).dup
    company.name = "Status Normalization Company"
    company.status = " Active "
    company.save!

    assert_equal "active", company.status
  end

  test "missing main URL scope finds blank URLs" do
    company = companies(:one).dup
    company.name = "Missing URL Company"
    company.main_url = ""
    company.save!

    assert_includes Company.missing_main_url, company
  end

  test "weak description scope finds short descriptions" do
    company = companies(:one).dup
    company.name = "Weak Description Company"
    company.description = "Short text"
    company.save!

    assert_includes Company.weak_description, company
  end

  test "quality status scopes find review states" do
    needs_review = companies(:one).dup
    needs_review.name = "Needs Review Company"
    needs_review.quality_status = "needs_review"
    needs_review.save!

    verified = companies(:one).dup
    verified.name = "Verified Company"
    verified.quality_status = "verified"
    verified.human_reviewed_at = Time.current
    verified.save!

    assert_includes Company.needs_review, needs_review
    assert_includes Company.verified_quality, verified
    assert_includes Company.human_reviewed, verified
  end

  test "duplicate name candidates use normalized names" do
    duplicate = companies(:one).dup
    duplicate.name = " test company one "
    duplicate.save!

    assert_includes Company.duplicate_name_candidates, companies(:one)
    assert_includes Company.duplicate_name_candidates, duplicate
  end

  test "duplicates by normalized name finds matching companies without loading all candidates" do
    duplicate = companies(:one).dup
    duplicate.name = " test company one "
    duplicate.save!

    matches = Company.duplicates_by_normalized_name_for(companies(:one))

    assert_includes matches, duplicate
    assert_not_includes matches, companies(:one)
  end

  test "duplicate name candidates preserve accented characters" do
    first = companies(:one).dup
    first.name = "Lega"
    first.main_url = "https://lega.ai"
    first.save!

    second = companies(:one).dup
    second.name = "Legaü"
    second.main_url = "https://legau.pt"
    second.save!

    assert_not_equal first.normalized_name, second.normalized_name
    assert_not_includes Company.duplicate_name_candidates, first
    assert_not_includes Company.duplicate_name_candidates, second
  end

  test "duplicate domain candidates use canonical domains" do
    duplicate = companies(:one).dup
    duplicate.name = "Duplicate Domain Company"
    duplicate.main_url = "https://www.example.com/path"
    duplicate.save!

    assert_includes Company.duplicate_domain_candidates, companies(:one)
    assert_includes Company.duplicate_domain_candidates, duplicate
  end

  test "duplicate domain candidates recalculate stale stored canonical domains" do
    duplicate = companies(:one).dup
    duplicate.name = "Stale Canonical Domain Company"
    duplicate.main_url = "https://www.example.com/path"
    duplicate.save!
    duplicate.update_columns(canonical_domain: "old-domain.example", updated_at: Time.current)

    assert_includes Company.duplicate_domain_candidates, companies(:one)
    assert_includes Company.duplicate_domain_candidates, duplicate
  end

  test "logo returns stored logo path when blob exists" do
    company = companies(:one)
    CompanyLogo.create!(company: company, data: "\x89PNG\r\n\x1a\n".b, content_type: "image/png")

    assert_equal Rails.application.routes.url_helpers.company_logo_path(company), company.logo
  end

  test "logo returns legacy external url when present" do
    company = companies(:one)
    company.update!(logo_url: "https://cdn.example.com/logo.png")

    assert_equal "https://cdn.example.com/logo.png", company.logo
  end

  test "logo ignores legacy logo dev urls without blob" do
    company = companies(:one)
    company.update!(logo_url: "https://img.logo.dev/example.com?token=pk_test")

    assert_match %r{\Ahttps://placehold\.co/}, company.logo
    assert company.logo_placeholder?
  end

  test "logo_placeholder is false when stored logo exists" do
    company = companies(:one)
    CompanyLogo.create!(company: company, data: "\x89PNG\r\n\x1a\n".b, content_type: "image/png")

    refute company.logo_placeholder?
  end

  test "sync_structured_location_fields parses location into country and city" do
    company = companies(:one)
    company.skip_geocoding = true
    company.update!(location: "Berlin, Germany")

    assert_equal "Germany", company.country
    assert_equal "Berlin", company.city
    assert_equal "Berlin, Germany", company.location
  end

  test "sync_structured_location_fields composes location from country and city" do
    company = companies(:one)
    company.skip_geocoding = true
    company.update!(country: "Netherlands", city: "Amsterdam", location: "Old value")

    assert_equal "Amsterdam, Netherlands", company.location
  end
end
