require "test_helper"

# What a reviewer can see about a duplicate on the record in front of them. The sidebar
# this covers used to list bare names on two keys, which could not distinguish a live
# public entry from an unpublished draft or from one already rejected — and those three
# resolve in opposite directions.
class CompanyDuplicateSurfaceTest < ActiveSupport::TestCase
  def company(name:, url: nil, **attrs)
    record = Company.create!(
      name: name, location: "Boston, MA", description: "Zephyr builds escrow reconciliation software for law firms.",
      category: categories(:one), target_client: target_clients(:one), business_models: [business_models(:one)],
      main_url: url
    )
    record.update_columns(attrs) if attrs.any?
    record.reload
  end

  test "an unpublished draft is reported, with its status, rather than passed over" do
    subject = company(name: "Pactolane", url: "https://pactolane.com")
    draft = company(name: "Pactolane", url: "https://pactolane.com")
    draft.update_columns(visible: false, canonical_domain: "pactolane.com")
    subject.update_columns(canonical_domain: "pactolane.com")

    match = CompanyDuplicateSurface.call(subject.reload).find { |m| m.company == draft }

    assert match, "a hidden draft on the same domain is exactly the row that would otherwise be minted twice"
    assert match.unresolved?
    assert_equal "Not public", match.visibility_label
  end

  test "a rejected entry is shown for context but does not stand in the way" do
    subject = company(name: "Gaskiya", url: "https://gaskiya.example")
    rejected = company(name: "Gaskiya", url: "https://gaskiya.example")
    rejected.update_columns(quality_status: "rejected")

    match = CompanyDuplicateSurface.call(subject.reload).find { |m| m.company == rejected }

    assert match, "a decision already made is still worth seeing"
    refute match.unresolved?, "a rejected duplicate has been resolved; it should not read as an open question"
    assert_equal "Rejected", match.status_label
  end

  test "a rebrand onto a new domain is caught by the name core" do
    subject = company(name: "ContractPodAi", url: "https://contractpodai.com")
    rebrand = company(name: "ContractPod Technologies", url: "https://leah.ai")

    match = CompanyDuplicateSurface.call(subject.reload).find { |m| m.company == rebrand }

    assert match, "neither the exact name nor the domain matches, which is what the core-name key is for"
    assert_equal [CompanyDuplicateSurface::CORE_NAME], match.reasons
  end

  test "one entry matching on several keys is reported once, with every reason" do
    subject = company(name: "Pactolane", url: "https://pactolane.com")
    twin = company(name: "Pactolane", url: "https://pactolane.com")
    [subject, twin].each { |record| record.update_columns(canonical_domain: "pactolane.com") }

    matches = CompanyDuplicateSurface.call(subject.reload).select { |m| m.company == twin }

    assert_equal 1, matches.size
    assert_includes matches.first.reasons, CompanyDuplicateSurface::DOMAIN
    assert_includes matches.first.reasons, CompanyDuplicateSurface::NAME
    refute_includes matches.first.reasons, CompanyDuplicateSurface::CORE_NAME,
                    "the core-name key should not repeat what the exact-name key already said"
  end

  test "unresolved matches sort ahead of ones already decided" do
    subject = company(name: "Lysias", url: "https://lysias.example")
    company(name: "Lysias", url: "https://lysias-old.example").update_columns(quality_status: "rejected")
    live = company(name: "Lysias", url: "https://lysias-two.example")

    assert_equal live, CompanyDuplicateSurface.call(subject.reload).first.company
  end

  test "a record with no twin says so rather than showing an empty list" do
    subject = company(name: "Zephyr Escrow Analytics", url: "https://zephyrescrow.example")

    assert_empty CompanyDuplicateSurface.call(subject)
  end
end
