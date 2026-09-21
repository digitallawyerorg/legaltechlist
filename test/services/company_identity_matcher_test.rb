require "test_helper"

# The cases here are real ones from the review queue: each test names the records it was
# drawn from, because the point of the matcher is to behave correctly on those and not on
# a synthetic ideal.
class CompanyIdentityMatcherTest < ActiveSupport::TestCase
  setup do
    @company = companies(:one)
    @other = companies(:two)
    [@company, @other].each { |company| company.update_columns(quality_status: nil, visible: true) }
  end

  def company!(attributes)
    columns = attributes.extract!(:canonical_domain, :quality_status, :visible, :slug, :quality_review, :url_health)
    @company.update!(attributes)
    @company.update_columns(columns) if columns.any?
    @company
  end

  def matches_for(name, url: nil, **kwargs)
    CompanyIdentityMatcher.matches_for(name: name, domains: [Company.canonical_domain_for(url)], **kwargs)
  end

  # ---- name normalization -------------------------------------------------

  test "core name ignores corporate form and glued product suffixes" do
    assert_equal "contractpod", CompanyIdentityMatcher.core_name("ContractPodAi")
    assert_equal "contractpod", CompanyIdentityMatcher.core_name("ContractPod Technologies")
    assert_equal "midpage", CompanyIdentityMatcher.core_name("Midpage AI")
    assert_equal "nextphone", CompanyIdentityMatcher.core_name("NextPhone Inc.")
  end

  # Legal forms arrive punctuated, and normalization splits them into single letters
  # before the token filter ever sees them.
  test "core name ignores punctuated and non-English corporate forms" do
    assert_equal "rolide", CompanyIdentityMatcher.core_name("ROLIDE S.R.L.")
    assert_equal "eucalypt", CompanyIdentityMatcher.core_name("Eucalypt s.r.o.")
    assert_equal "kancelaria", CompanyIdentityMatcher.core_name("Kancelaria Sp. z o.o.")
    assert_equal "enhanced work nordic", CompanyIdentityMatcher.core_name("Enhanced Work Nordic AB")
    assert_equal "unison laboratories", CompanyIdentityMatcher.core_name("Unison Laboratories B.V.")
  end

  # Punctuation and spacing are not identity. Searching "Deep-Law" returned only one of
  # the two records and "Deep Law" returned only the other.
  test "core key folds punctuation and spacing so the same brand compares equal" do
    assert_equal CompanyIdentityMatcher.core_key("Deep-Law"), CompanyIdentityMatcher.core_key("Deep Law")
    assert_equal CompanyIdentityMatcher.core_key("Deep Law"), CompanyIdentityMatcher.core_key("deeplaw")
    assert_equal CompanyIdentityMatcher.core_key("LegalSparrow"), CompanyIdentityMatcher.core_key("Legal Sparrow")
  end

  test "core name refuses to assert identity on generic, filler or tiny names" do
    ["Legal AI", "Contracts Ltd", "Legal.io", "Law Group", "AB", "Platform that", "Online platform that", "The company"].each do |name|
      assert_nil CompanyIdentityMatcher.core_name(name), "#{name.inspect} should not carry a duplicate claim"
    end
  end

  test "core name keeps place names whose ending resembles a product suffix" do
    assert_equal "mumbai legal", CompanyIdentityMatcher.core_name("Mumbai Legal")
    assert_equal "dubai counsel", CompanyIdentityMatcher.core_name("Dubai Counsel")
  end

  # ---- FALSE POSITIVES the matcher must not produce -----------------------

  # Contracts 365, Inc. (Newburyport, US) was rejected as a duplicate of Cloud Contracts
  # 365 Ltd. (Tunbridge Wells, UK) on a core-name match and nothing else, because "cloud"
  # was stripped as a noise word wherever it appeared. A leading descriptive word is part
  # of the brand.
  test "a leading descriptive word is part of the brand, not a strippable suffix" do
    company!(name: "Cloud Contracts 365", main_url: "https://www.cloudcontracts365.com/", canonical_domain: "cloudcontracts365.com")

    assert_empty matches_for("Contracts 365", url: "https://www.contracts365.com"),
                 "two companies in two countries must not meet on a stripped leading word"
    refute_equal CompanyIdentityMatcher.core_key("Cloud Contracts 365"), CompanyIdentityMatcher.core_key("Contracts 365")
  end

  # 222 Injury Lawyers PLLC (Tulsa) and Midwest Injury Lawyers are different firms whose
  # names share two generic legal-industry nouns.
  test "distinct firms sharing generic industry nouns do not match" do
    company!(name: "Midwest Injury Lawyers", main_url: "https://midwestinjurylawyers.example", canonical_domain: "midwestinjurylawyers.example")

    assert_empty matches_for("222 Injury Lawyers PLLC", url: "https://222injurylawyers.example")
  end

  # Specteria Technologies (Colombia) is a name-prefix coincidence with SpecterAI, and was
  # named in review as exactly the false positive the domain rule exists to catch.
  test "a shared name prefix is not a match" do
    company!(name: "Specteria Technologies", main_url: "https://specteria.com", canonical_domain: "specteria.com")

    assert_empty matches_for("SpecterAI", url: "https://specterlaw.ai")
  end

  # A host that hands out tenant subdomains gives unrelated companies one domain.
  test "two tenants under one host are not the same company" do
    company!(name: "Tenant One", main_url: "https://tenant-one.wixsite.com", canonical_domain: "tenant-one.wixsite.com")

    assert_empty matches_for("Tenant Two", url: "https://tenant-two.wixsite.com")
    refute CompanyIdentityMatcher.related_domains?("tenant-one.wixsite.com", "wixsite.com")
    refute CompanyIdentityMatcher.related_domains?("acme.somehost.com", "somehost.com"),
           "an arbitrary subdomain label is a tenant name, not a different door"
  end

  # Intake validates nothing: a company name has arrived sitting in linkedin_url.
  test "profile matching ignores anything that is not a company page" do
    assert_nil CompanyIdentityMatcher.profile_key("linkedin", "FPS Database")
    assert_nil CompanyIdentityMatcher.profile_key("linkedin", "https://www.linkedin.com/in/some-person")
    assert_nil CompanyIdentityMatcher.profile_key("linkedin", "http://linkedin.com/example")
    assert_equal "linkedin:caseway-ai", CompanyIdentityMatcher.profile_key("linkedin", "https://www.linkedin.com/company/caseway-ai/")
  end

  test "records with unparseable profile urls do not match each other" do
    company!(name: "Unrelated Entry", main_url: "https://unrelated-entry.example", canonical_domain: "unrelated-entry.example",
             linkedin_url: "FPS Bench", crunchbase_url: "FPS Database")

    assert_empty CompanyIdentityMatcher.matches_for(
      name: "Another Entry",
      domains: ["another-entry.example"],
      profiles: CompanyIdentityMatcher.profile_keys("linkedin_url" => "FPS Bench", "crunchbase_url" => "FPS Database")
    )
  end

  # The duplicate panels on proposals 4179 and 4378 both named proposal 3827 (Tecnika
  # Legal), described as "matched on brand name". The records are unrelated: all three
  # were cited from Crunchbase, and the brand label of crunchbase.com is "crunchbase" for
  # every one of them. An aggregator, registry or social page is not a company's address,
  # so it supplies neither a domain nor a brand.
  test "an aggregator page is not an address, so two records citing one do not match" do
    company!(name: "Tecnika Legal", main_url: "https://www.crunchbase.com/organization/tecnika-legal",
             canonical_domain: "crunchbase.com")

    assert_empty matches_for("Harbor Clause Review", url: "https://www.crunchbase.com/organization/harbor-clause-review"),
                 "two records on one aggregator share a host, not an identity"
    assert_empty matches_for("Harbor Clause Review", url: "https://de.crunchbase.com/organization/harbor-clause-review"),
                 "and not a brand label either, which is the key the 4179 panel reported"
    assert_empty matches_for("Harbor Clause Review", url: "https://www.linkedin.com/company/harbor-clause-review")

    assert_nil CompanyIdentityMatcher.brand_key("crunchbase.com")
    assert_nil CompanyIdentityMatcher.brand_key("uk.linkedin.com")
    assert_nil CompanyIdentityMatcher.brand_key("opencorporates.com")
    assert_nil CompanyIdentityMatcher.brand_key("linktr.ee")
    refute CompanyIdentityMatcher.related_domains?("www.crunchbase.com", "crunchbase.com")
  end

  # The other half of that rule: linkedin.com stops being an address, but a shared
  # LinkedIn *company page* is still the strongest key in the system, and it is read from
  # linkedin_url rather than from any domain. Losing it would blind the good path.
  test "a shared linkedin company page still matches when linkedin is not an address" do
    company!(name: "Vantoria", main_url: "https://www.linkedin.com/company/vantoria",
             canonical_domain: "linkedin.com",
             linkedin_url: "https://www.linkedin.com/company/vantoria")

    match = CompanyIdentityMatcher.matches_for(
      name: "Pellumbra",
      domains: ["linkedin.com"],
      profiles: CompanyIdentityMatcher.profile_keys("linkedin_url" => "https://linkedin.com/company/vantoria/")
    ).first

    assert match, "the company page survives even when neither record has a site of its own"
    assert_equal "shared_profile", match["match_type"]
    assert_equal ["shared_profile"], match["match_types"],
                 "the shared host must not also be reported as a shared domain or brand"
    assert_equal CompanyIdentityMatcher::CONFIDENCE_CONFIRMED, match["confidence"]
  end

  # ---- FALSE NEGATIVES the matcher must now catch -------------------------

  # Proposal 4139 (deep-law.com) was not flagged against public company 16479, which
  # publishes Deep Law at deep-law.io under the company name D-Developments. Nothing
  # matched: not the name, not the domain, and no query returned both records.
  test "the same brand on another TLD matches even when neither name mentions it" do
    company!(name: "D-Developments", main_url: "https://deep-law.io", canonical_domain: "deep-law.io")

    match = matches_for("White Rabbit (Deep-Law)", url: "https://deep-law.com").first

    assert match, "a brand published on another TLD must be flagged"
    assert_equal @company.id, match["id"]
    assert_equal "brand_name", match["match_type"]
    assert_equal "deeplaw", match["matched_value"]
    # Three unrelated products have shipped as "Deep Law". This needs comparing, not merging.
    assert_equal CompanyIdentityMatcher::CONFIDENCE_POSSIBLE, match["confidence"]
  end

  # Proposal 4279 was submitted as "Unison Labs" for the product sixminute.ai, and the row
  # it minted is still named for the parent, so an intake naming the product missed.
  test "a product named only in the domain matches a submission naming the product" do
    company!(name: "Unison Labs", main_url: "https://sixminute.ai", canonical_domain: "sixminute.ai")

    match = matches_for("Sixminute", url: "https://sixminute.com").first

    assert match, "the product name in the existing entry's domain must be matchable"
    assert_equal "brand_name", match["match_type"]
  end

  # Company 13192 was renamed from eSignLive to OneSpan; a submission under the old brand
  # found nothing, because only the current name was compared.
  test "a submission under a name the entry used to carry matches via the slug" do
    company!(name: "OneSpan", main_url: "https://onespan.com", canonical_domain: "onespan.com", slug: "esignlive")

    match = matches_for("eSignLive", url: "https://esignlive.example").first

    assert match, "the slug outlives a rename and is the cheapest record of a prior name"
    assert_equal "prior_name", match["match_type"]
  end

  test "a prior name recorded in the field-edit history matches" do
    company!(name: "Margo Legal", main_url: "https://margolegal.com", canonical_domain: "margolegal.com", slug: "margo-legal",
             quality_review: { "field_edits" => [{ "changes" => { "name" => { "from" => "ClickoAI", "to" => "Margo Legal" } } }] })

    assert_equal "prior_name", matches_for("Clickoai", url: "https://clickoai.example").first&.dig("match_type")
  end

  # Proposal 4001 is published as "Alentra" while describing ProseID; 4167 Notaron matched
  # its published entry on domain, name, LinkedIn and Crunchbase at once.
  test "a shared linkedin company page matches across a different name and domain" do
    company!(name: "Alentra", main_url: "https://alentra.app", canonical_domain: "alentra.app",
             linkedin_url: "https://www.linkedin.com/company/proseid")

    match = CompanyIdentityMatcher.matches_for(
      name: "ProseID",
      domains: ["proseid.com"],
      profiles: CompanyIdentityMatcher.profile_keys("linkedin_url" => "https://linkedin.com/company/proseid/")
    ).first

    assert match, "a shared company page survives both a rename and a domain move"
    assert_equal "shared_profile", match["match_type"]
    assert_equal CompanyIdentityMatcher::CONFIDENCE_CONFIRMED, match["confidence"]
  end

  # Hidden mints are the state every recent approval left its company in, and a guard that
  # cannot see them blinds itself for that domain: the next approval mints another row.
  test "a hidden draft matches and reports itself as not visible" do
    company!(name: "SpecterAI", main_url: "https://specterlaw.ai", canonical_domain: "specterlaw.ai", visible: false)

    match = matches_for("SpecterAI", url: "https://specterlaw.ai").first

    assert match
    refute match["visible"], "the reviewer has to be told this one is not public"
  end

  # An auto-applied main_url change does not recompute canonical_domain, so the record
  # became invisible to a check on its own current website.
  test "a stale canonical domain does not hide a match on the current website" do
    company!(name: "CASUS", main_url: "https://www.getcasus.com/", canonical_domain: "casus.ch")

    assert matches_for("Anything Else", url: "https://getcasus.com").first, "the live main_url must match"
    assert matches_for("Anything Else", url: "https://casus.ch").first, "the stored domain must still match"
  end

  test "a subdomain entrance matches the domain it fronts" do
    company!(name: "Portal Co", main_url: "https://portalco.example", canonical_domain: "portalco.example")

    assert_equal "related_domain", matches_for("Portal Co Apps", url: "https://app.portalco.example").first&.dig("match_type")
  end

  # The eSignLive entry's own site resolves to onespan.com, so a submission under the new
  # brand matches a domain the stored record never declared. This is the strongest rebrand
  # signal in the system and the one the guard already had.
  test "an entry whose site resolves to the candidate's domain matches as a rebrand" do
    company = company!(name: "eSignLive", main_url: "https://esignlive.com", canonical_domain: "esignlive.com")
    company.update_columns(url_health: { "final_url" => "https://onespan.com/" })

    matcher = CompanyIdentityMatcher.new(name: "OneSpan", domains: ["onespan.com"])
    match = matcher.matches.first

    assert_equal "redirect_domain", match["match_type"]
    assert_equal "onespan.com", match["matched_value"]
    assert_equal CompanyIdentityMatcher::CONFIDENCE_CONFIRMED, match["confidence"]
    assert matcher.rebrand?(match), "a domain the stored record never declared is a rebrand"
  end

  test "diacritics fold so an accented name matches its unaccented spelling" do
    company!(name: "White Rabbit Bilişim", main_url: "https://whiterabbitbilisim.example", canonical_domain: "whiterabbitbilisim.example")

    assert matches_for("White Rabbit Bilisim", url: "https://elsewhere.example").first
  end

  # ---- reporting ----------------------------------------------------------

  test "a record matching on several keys reports all of them" do
    company!(name: "Notaron", main_url: "https://notaron.com/", canonical_domain: "notaron.com",
             linkedin_url: "https://www.linkedin.com/company/notaron")

    match = CompanyIdentityMatcher.matches_for(
      name: "Notaron",
      domains: ["notaron.com"],
      profiles: CompanyIdentityMatcher.profile_keys("linkedin_url" => "https://www.linkedin.com/company/notaron")
    ).first

    assert_equal "exact_domain", match["match_type"]
    assert_includes match["match_types"], "exact_name"
    assert_includes match["match_types"], "shared_profile"
    assert_equal %w[linkedin], match["shared_profiles"]
    assert_equal CompanyIdentityMatcher::CONFIDENCE_CONFIRMED, match["confidence"]
  end

  test "a rejected entry is out of the way" do
    company!(name: "Rejected Entry", main_url: "https://rejected-entry.example", canonical_domain: "rejected-entry.example", quality_status: "rejected")

    assert_empty matches_for("Rejected Entry", url: "https://rejected-entry.example")
  end

  test "a named company is excluded from its own comparison" do
    company!(name: "Self Match", main_url: "https://selfmatch.example", canonical_domain: "selfmatch.example")

    assert_empty matches_for("Self Match", url: "https://selfmatch.example", exclude_company_id: @company.id)
  end
end
