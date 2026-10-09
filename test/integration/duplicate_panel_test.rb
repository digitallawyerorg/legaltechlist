require "test_helper"

# The reviewer-facing Duplicate check panel on a proposal, on the shape that produced
# both complaints against proposal 4675 / Apertera #11445: an index entry that agrees
# with the candidate on BOTH an address key and a name key, and whose stored
# canonical_domain predates a rebrand.
#
# ProposalDuplicateDetectorService reports one such hit in two lists — "name_matches"
# and "domain_matches" are selections over the same array — and the matcher's index row
# carries the stale companies.canonical_domain ahead of the domain derived from
# main_url, because that column is not recomputed when main_url changes.
class DuplicatePanelTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # The June 2026 rename: the entry publishes apertera.com and is named Apertera, while
  # the canonical_domain column still holds the name it was indexed under.
  setup do
    sign_in admin_users(:one)
    @company = companies(:one)
    @company.update!(name: "Apertera", main_url: "https://apertera.com")
    @company.update_columns(canonical_domain: "alexatranslations.com", quality_status: nil)

    @proposal = CompanyProposal.create!(
      status: "ready_for_review", proposal_type: "discovery_candidate", source: "llm_discovery",
      source_identifier: SecureRandom.uuid, source_payload: {}, duplicate_signals: {},
      proposed_changes: { "name" => "Apertera", "main_url" => "https://apertera.com" },
      final_changes: { "name" => "Apertera", "main_url" => "https://apertera.com" }
    )
  end

  # The pair this panel is about really is a duplicate, and it really does stop an
  # approval: an address key and a name key from two independent families. Asserting
  # only that "something matched" would let a change to the surfacing rule through.
  test "an entry agreeing on both an address key and a name key blocks" do
    signals = @proposal.current_duplicate_signals
    hit = signals["domain_matches"].find { |match| match["id"] == @company.id }

    assert_equal CompanyIdentityMatcher::SURFACING_BLOCKING, hit["surfacing"]
    assert signals["blocking"], "two agreeing families is a blocking duplicate, not an advisory one"
    refute signals["advisory"]
    assert_equal %w[exact_domain exact_name core_name brand_name], hit["match_types"]
  end

  # Defect 1. The hit is in both lists; the reviewer must still see one row per record.
  test "a record matching on two families is reported once" do
    signals = @proposal.current_duplicate_signals

    assert_equal [@company.id], signals["name_matches"].map { |match| match["id"] }
    assert_equal [@company.id], signals["domain_matches"].map { |match| match["id"] },
                 "the same hit is in both lists, which is what the panel has to collapse"
    assert_equal [@company.id], @proposal.duplicate_matches.map { |match| match["id"] }
  end

  test "the panel draws each matched record once" do
    get custom_admin_company_proposal_path(@proposal)

    assert_response :success
    assert_select "a[href=?]", custom_admin_company_review_path(@company.id), count: 1,
                  message: "one row per matched record, not one per match key"
    assert_select "a[href=?]", compare_duplicate_custom_admin_company_proposal_path(@proposal, company_id: @company.id), count: 1
  end

  # Defect 2. The match fired on apertera.com. alexatranslations.com is the entry's
  # stale canonical_domain column and was never compared against anything.
  test "the card names the domain the match fired on, not the entry's stored domain" do
    hit = @proposal.current_duplicate_signals["domain_matches"].first

    assert_equal "apertera.com", hit["matched_value"]
    assert_equal "alexatranslations.com", hit["canonical_domain"]

    get custom_admin_company_proposal_path(@proposal)

    assert_response :success
    assert_includes @response.body, "matched on exact domain (apertera.com)"
    refute_match(/matched on exact domain \(alexatranslations\.com\)/, @response.body)
    assert_includes @response.body, "entry is listed at alexatranslations.com"
  end

  # Both keys, strongest first, on the one row — the way the review-queue half of the
  # same panel has always listed them.
  test "the card lists every key that agreed" do
    get custom_admin_company_proposal_path(@proposal)

    assert_includes @response.body, "matched on exact domain (apertera.com), exact name, core name, and brand name"
  end
end
