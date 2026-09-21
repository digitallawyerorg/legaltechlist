require "test_helper"

class ProposalDuplicateDetectorServiceTest < ActiveSupport::TestCase
  setup do
    @company = companies(:one)
    @company.update!(name: "ContractPod Technologies", main_url: "https://contractpodai.com")
    @company.update_columns(canonical_domain: "contractpodai.com", quality_status: nil)
  end

  def proposal_for(changes, status: "pending", source_payload: {})
    CompanyProposal.create!(
      status: status,
      proposal_type: "discovery_candidate",
      source: "llm_discovery",
      source_identifier: SecureRandom.uuid,
      source_payload: source_payload,
      proposed_changes: changes,
      final_changes: changes,
      duplicate_signals: {}
    )
  end

  # ---- core-name normalization -------------------------------------------

  test "core name ignores corporate form and glued product suffixes" do
    assert_equal "contractpod", ProposalDuplicateDetectorService.core_name("ContractPodAi")
    assert_equal "contractpod", ProposalDuplicateDetectorService.core_name("ContractPod Technologies")
    assert_equal "midpage", ProposalDuplicateDetectorService.core_name("Midpage AI")
    assert_equal "midpage", ProposalDuplicateDetectorService.core_name("Midpage")
    assert_equal "nextphone", ProposalDuplicateDetectorService.core_name("NextPhone Inc.")
  end

  # Found by checking the live index: three scrape artifacts named "Platform that",
  # "Platform that" and "Online platform that" were grouped as duplicates of each other
  # on the core "that", which asserts nothing about identity.
  test "core name refuses to assert identity on a filler word" do
    assert_nil ProposalDuplicateDetectorService.core_name("Platform that")
    assert_nil ProposalDuplicateDetectorService.core_name("Online platform that")
    assert_nil ProposalDuplicateDetectorService.core_name("The company")
    assert_equal "clausedelta", ProposalDuplicateDetectorService.core_name("ClauseDelta platform"),
                 "a real name alongside a filler word still resolves"
  end

  test "core name refuses to assert identity on a generic or tiny core" do
    assert_nil ProposalDuplicateDetectorService.core_name("Legal AI")
    assert_nil ProposalDuplicateDetectorService.core_name("Contracts Ltd")
    assert_nil ProposalDuplicateDetectorService.core_name("Legal.io")
    assert_nil ProposalDuplicateDetectorService.core_name("Law Group")
    assert_nil ProposalDuplicateDetectorService.core_name("AB")
  end

  test "core name keeps place names whose ending resembles a product suffix" do
    assert_equal "mumbai legal", ProposalDuplicateDetectorService.core_name("Mumbai Legal")
    assert_equal "dubai counsel", ProposalDuplicateDetectorService.core_name("Dubai Counsel")
  end

  # ---- company matching --------------------------------------------------

  test "flags an exact domain match against the live index" do
    signals = ProposalDuplicateDetectorService.call(proposal: proposal_for({"name" => "Totally Different", "main_url" => "https://contractpodai.com"}))

    assert signals["blocking"]
    assert_equal ["exact_domain"], signals["domain_matches"].map { |m| m["match_type"] }
    assert_equal @company.id, signals["domain_matches"].first["id"]
  end

  test "flags a rebrand whose name and declared domain both differ, via the fetched domain" do
    proposal = proposal_for({"name" => "ContractPodAi", "main_url" => "https://leahai.com/"})

    # Neither key matches on its own: "contractpodai" is not "contractpod technologies",
    # and leahai.com is not contractpodai.com.
    plain = ProposalDuplicateDetectorService.call(proposal: proposal)
    assert_equal ["core_name"], plain["name_matches"].map { |m| m["match_type"] },
                 "core-name should still catch the rebrand by name"

    # And when the site fetch resolves the redirect, the domain key catches it too.
    resolved = ProposalDuplicateDetectorService.call(proposal: proposal, extra_domains: ["contractpodai.com"])
    assert_equal ["exact_domain"], resolved["domain_matches"].map { |m| m["match_type"] }
    assert resolved["blocking"], "a real rebrand caught on the fetched domain has to stay blocking"
    assert_match(/rebrand/, resolved["recommended_action"])
  end

  test "matches a hidden draft, which would otherwise mint a second row" do
    @company.update_columns(visible: false)
    signals = ProposalDuplicateDetectorService.call(proposal: proposal_for({"name" => "ContractPod Technologies"}))

    assert signals["blocking"]
    refute signals["name_matches"].first["visible"]
  end

  test "ignores a rejected company" do
    @company.update_columns(quality_status: "rejected")
    signals = ProposalDuplicateDetectorService.call(proposal: proposal_for({"name" => "ContractPod Technologies"}))

    refute signals["blocking"]
  end

  test "reports no match for an unrelated candidate" do
    signals = ProposalDuplicateDetectorService.call(proposal: proposal_for({"name" => "Zephyr Escrow Analytics", "main_url" => "https://zephyrescrow.example"}))

    refute signals["blocking"]
    assert_empty signals["name_matches"]
    assert_empty signals["domain_matches"]
    assert_nil signals["recommended_action"]
  end

  # A candidate's source_url is the page it was cited from, not an address it claims.
  # Discovery routinely cites a vendor directory, a registry entry or a market-map post
  # — and those pages are often hosted by another company that is already in the index.
  # Treating the citation as one of the candidate's own domains made exact_domain, the
  # highest-precedence key, fire between an unrelated company and whoever happens to
  # host the page it was found on.
  test "a citation hosted on an indexed company's domain is not the candidate's own domain" do
    signals = ProposalDuplicateDetectorService.call(proposal: proposal_for({
      "name" => "Zephyr Escrow Analytics",
      "main_url" => "https://zephyrescrow.example",
      "source_url" => "https://contractpodai.com/resources/legal-tech-directory"
    }))

    refute signals["blocking"], "a directory page on another company's site is not shared identity"
    assert_empty signals["domain_matches"]
    assert_empty signals["name_matches"]
    assert_nil signals["recommended_action"]
  end

  # The other half: dropping source_url costs nothing, because a citation on the
  # candidate's own site says only what main_url already said.
  test "a citation on the candidate's own site still matches through main_url" do
    signals = ProposalDuplicateDetectorService.call(proposal: proposal_for({
      "name" => "Totally Different",
      "main_url" => "https://contractpodai.com",
      "source_url" => "https://contractpodai.com/about-us"
    }))

    assert signals["blocking"]
    assert_equal ["exact_domain"], signals["domain_matches"].map { |m| m["match_type"] }
    assert_equal @company.id, signals["domain_matches"].first["id"]
  end

  # ---- sibling-proposal matching -----------------------------------------

  test "two open proposals for the same company see each other" do
    first = proposal_for({ "name" => "Pactolane", "main_url" => "https://www.pactolane.com" }, status: "ready_for_review")
    second = proposal_for({"name" => "Pactolane", "main_url" => "https://www.pactolane.com"})

    signals = ProposalDuplicateDetectorService.call(proposal: second)
    match = signals["proposal_matches"].find { |m| m["proposal_id"] == first.id }

    assert signals["blocking"]
    assert match, "expected the sibling proposal to be reported"
    assert match["is_older"], "the earlier record should be marked as such"
    assert_match(/Proposal ##{first.id} covers the same company/, signals["recommended_action"])
  end

  test "a resolved sibling drops out of the comparison set" do
    first = proposal_for({ "name" => "Gaskiya" }, status: "ready_for_review")
    second = proposal_for({"name" => "Gaskiya"})

    assert ProposalDuplicateDetectorService.call(proposal: second)["blocking"]

    first.update!(status: "rejected")
    refute ProposalDuplicateDetectorService.call(proposal: second)["blocking"]
  end

  test "a proposal is not a duplicate of the company it created itself" do
    proposal = proposal_for({ "name" => "ContractPod Technologies", "main_url" => "https://contractpodai.com" })
    assert ProposalDuplicateDetectorService.call(proposal: proposal)["blocking"]

    proposal.update!(company: @company)
    refute ProposalDuplicateDetectorService.call(proposal: proposal)["blocking"],
           "promoting an approved draft must not be blocked by the row the proposal itself minted"
  end

  test "a proposal rejected as a duplicate still reports the entry that was kept" do
    proposal = proposal_for({ "name" => "ContractPod Technologies", "main_url" => "https://contractpodai.com" })
    proposal.update!(status: "rejected", company: @company)

    assert ProposalDuplicateDetectorService.call(proposal: proposal)["blocking"],
           "the company link on a rejected duplicate records what was kept, not what it created"
  end

  test "a proposal never matches itself" do
    proposal = proposal_for({"name" => "Solo Candidate", "main_url" => "https://solo.example"})

    assert_empty ProposalDuplicateDetectorService.call(proposal: proposal)["proposal_matches"]
  end

  # Europaius 4113/4114 and Epistemic Labs 4102/4103 were each one company with two
  # genuinely distinct products on one website, and were correctly held apart rather than
  # merged. The sibling comparison graded nothing, so the reviewer was told to reject one.
  test "two open proposals sharing a website with different product names are only possible" do
    first = proposal_for({ "name" => "Epistemic Labs Clause Engine", "main_url" => "https://epistemiclabs.example" }, status: "ready_for_review")
    second = proposal_for({"name" => "Epistemic Labs Deposition Copilot", "main_url" => "https://epistemiclabs.example"})

    signals = ProposalDuplicateDetectorService.call(proposal: second)
    match = signals["proposal_matches"].find { |m| m["proposal_id"] == first.id }

    assert match, "expected the sibling proposal to be reported"
    assert_equal "exact_domain", match["match_type"]
    assert_equal ProposalDuplicateDetectorService::CONFIDENCE_POSSIBLE, match["confidence"]
    assert signals["blocking"], "a possible match is still a comparison a human has to make"
    assert_match(/two products from one company/, signals["recommended_action"])
    assert_match(/compare the two records/, signals["recommended_action"])
    refute_match(/keep one and reject the other/, signals["recommended_action"])
  end

  # A shared company page is the only key that survives both a rename and a domain move —
  # proposal 4001 is published as "Alentra" while describing ProseID — and between two
  # proposals it was invisible, because the sibling side never read their profile urls.
  test "two open proposals sharing a linkedin company page match on the shared profile" do
    first = proposal_for({ "name" => "Alentra", "main_url" => "https://alentra.app",
                           "linkedin_url" => "https://www.linkedin.com/company/proseid" }, status: "ready_for_review")
    second = proposal_for({"name" => "ProseID", "main_url" => "https://proseid.com",
                           "linkedin_url" => "https://linkedin.com/company/proseid/"})

    signals = ProposalDuplicateDetectorService.call(proposal: second)
    match = signals["proposal_matches"].find { |m| m["proposal_id"] == first.id }

    assert match, "a shared company page has to be visible between two proposals"
    assert_equal "shared_profile", match["match_type"]
    assert_equal ProposalDuplicateDetectorService::CONFIDENCE_CONFIRMED, match["confidence"]
    assert signals["blocking"]
  end

  # The 4179 / 3827 shape. The duplicate panels on proposals 4179 and 4378 both listed
  # proposal 3827 (Tecnika Legal) as a match, reasoned "matched on brand name". The three
  # records have nothing in common but a Crunchbase citation standing in for a website,
  # and crunchbase.com reads as the brand "crunchbase" on all of them. A page about a
  # company is not that company's address, on either side of the comparison.
  test "two proposals whose only shared key is an aggregator brand do not see each other" do
    tecnika = proposal_for({ "name" => "Tecnika Legal",
                             "main_url" => "https://www.crunchbase.com/organization/tecnika-legal" },
                           status: "ready_for_review")
    same_host = proposal_for({"name" => "Harbor Clause Review",
                              "main_url" => "https://www.crunchbase.com/organization/harbor-clause-review"})
    other_host = proposal_for({"name" => "Orrinbeck Disclosure",
                               "main_url" => "https://de.crunchbase.com/organization/orrinbeck-disclosure"})

    [same_host, other_host].each do |candidate|
      signals = ProposalDuplicateDetectorService.call(proposal: candidate)

      assert_nil signals["proposal_matches"].find { |match| match["proposal_id"] == tecnika.id },
                 "proposal ##{candidate.id} must not name an unrelated record it merely shares an aggregator with"
      assert_empty signals["proposal_matches"]
      assert_empty signals["domain_matches"]
      assert_empty signals["name_matches"]
      refute signals["blocking"]
      assert_nil signals["recommended_action"]
    end
  end

  # ---- surfacing ---------------------------------------------------------

  # The pair the reviewer reported, with the host the exclusion list does not name.
  # Batesly and Tecnika Legal arrive with no site of their own and a store or directory
  # listing standing in for one. The hit is still reported and still graded; it stops
  # asserting a duplicate by itself once the population shows the host is a place
  # records get put rather than an address either of them owns.
  test "two proposals sharing only an aggregator address are advisory, not blocking" do
    first = proposal_for({ "name" => "Batesly", "main_url" => "https://www.producthunt.com/products/batesly" }, status: "ready_for_review")
    proposal_for({ "name" => "Third Listing", "main_url" => "https://www.producthunt.com/products/third-listing" }, status: "ready_for_review")
    second = proposal_for({"name" => "Tecnika Legal", "main_url" => "https://www.producthunt.com/products/tecnika-legal"})

    signals = ProposalDuplicateDetectorService.call(proposal: second)
    match = signals["proposal_matches"].find { |m| m["proposal_id"] == first.id }

    assert match, "the comparison is still offered to the reviewer"
    assert_equal "exact_domain", match["match_type"]
    assert_equal CompanyIdentityMatcher::OWNERSHIP_SHARED, match["domain_ownership"]
    assert_equal CompanyIdentityMatcher::SURFACING_ADVISORY, match["surfacing"]
    refute signals["blocking"]
    assert signals["advisory"]
    assert_match(/Not treated as a duplicate/, signals["recommended_action"])
  end

  # The ownership measurement was split across two populations that could not see each
  # other: the matcher counted index rows, the sibling side counted open proposals. The
  # same pair then read "owned" on one side and "shared" on the other, and one call came
  # back with blocking and advisory both true.
  test "one domain gets one verdict whether it is read from the index or the open queue" do
    @company.update!(name: "Indexed Listing", main_url: "https://www.producthunt.com/products/indexed-listing")
    @company.update_columns(canonical_domain: "producthunt.com", visible: true, quality_status: nil)
    second_indexed = companies(:two)
    second_indexed.update!(name: "Second Indexed Listing", main_url: "https://www.producthunt.com/products/second-indexed")
    second_indexed.update_columns(canonical_domain: "producthunt.com", visible: true, quality_status: nil)

    sibling = proposal_for({ "name" => "Batesly", "main_url" => "https://www.producthunt.com/products/batesly" }, status: "ready_for_review")
    candidate = proposal_for({"name" => "Tecnika Legal", "main_url" => "https://www.producthunt.com/products/tecnika-legal"})

    signals = ProposalDuplicateDetectorService.call(proposal: candidate)
    company_match = signals["domain_matches"].find { |match| match["id"] == @company.id }
    sibling_match = signals["proposal_matches"].find { |match| match["proposal_id"] == sibling.id }

    assert company_match, "the index row on the shared host is still reported"
    assert sibling_match, "and so is the sibling proposal on it"
    assert_equal CompanyIdentityMatcher::OWNERSHIP_SHARED, company_match["domain_ownership"]
    assert_equal CompanyIdentityMatcher::OWNERSHIP_SHARED, sibling_match["domain_ownership"],
                 "the index and the open queue are one population, so one domain gets one verdict"
    refute signals["blocking"], "the same host must not read blocking on one side and advisory on the other"
    assert signals["advisory"]
  end

  # The reviewer's complaint was a weak single key worded exactly like a confirmed
  # duplicate, and appending "not treated as a duplicate" to that sentence left the
  # claim first and the retraction last, with the ask repeated twice.
  test "an advisory action opens with the retraction and does not say it twice" do
    sibling = proposal_for({ "name" => "Pactolane", "main_url" => "https://www.pactolane.com" }, status: "ready_for_review")
    candidate = proposal_for({"name" => "Pactolane Technologies", "main_url" => "https://pactolane-clm.example"})

    action = ProposalDuplicateDetectorService.call(proposal: candidate)["recommended_action"]

    assert action.start_with?("Not treated as a duplicate"), action
    assert_match(/proposal ##{sibling.id}/, action)
    assert_match(/core name and brand name agreed/, action)
    refute_match(/may cover the same company/, action)
    refute_match(/Possibly the same company/, action)
    assert_equal 1, action.scan(/ompare the/).size, "the reviewer is asked to compare exactly once"
  end

  # A core-name agreement and the brand label read out of that same core are one
  # reading of two names, not two.
  test "two proposals agreeing on a core name alone are advisory" do
    first = proposal_for({ "name" => "Pactolane", "main_url" => "https://www.pactolane.com" }, status: "ready_for_review")
    second = proposal_for({"name" => "Pactolane Technologies", "main_url" => "https://pactolane-clm.example"})

    signals = ProposalDuplicateDetectorService.call(proposal: second)
    match = signals["proposal_matches"].find { |m| m["proposal_id"] == first.id }

    assert match
    assert_equal %w[core_name brand_name], match["match_types"]
    assert_equal CompanyIdentityMatcher::SURFACING_ADVISORY, match["surfacing"]
    refute signals["blocking"]
    assert signals["advisory"]
  end

  # Authedra 4148/4164: two open proposals for one company, judged a correct duplicate
  # call, carried by the name and nothing else. exact_name is what has to hold it.
  test "twin proposals with one name and no website still block on the name alone" do
    first = proposal_for({ "name" => "Authedra" }, status: "ready_for_review")
    second = proposal_for({"name" => "Authedra"})

    signals = ProposalDuplicateDetectorService.call(proposal: second)
    match = signals["proposal_matches"].find { |m| m["proposal_id"] == first.id }

    assert_equal "exact_name", match["match_type"]
    assert_equal CompanyIdentityMatcher::SURFACING_BLOCKING, match["surfacing"]
    assert signals["blocking"]
    refute_match(/Not treated as a duplicate/, signals["recommended_action"])
  end

  # Caseway 4174/4175 and the Europaius double-post: one submission that arrived twice.
  # Grading the sibling side must not soften these — they are one record, not two products.
  test "twin proposals with the same name and website stay confirmed" do
    first = proposal_for({ "name" => "Caseway", "main_url" => "https://caseway.ai" }, status: "ready_for_review")
    second = proposal_for({"name" => "Caseway", "main_url" => "https://caseway.ai"})

    signals = ProposalDuplicateDetectorService.call(proposal: second)
    match = signals["proposal_matches"].find { |m| m["proposal_id"] == first.id }

    assert match
    assert_equal "exact_domain", match["match_type"]
    assert_includes match["match_types"], "exact_name"
    assert_equal ProposalDuplicateDetectorService::CONFIDENCE_CONFIRMED, match["confidence"]
    assert signals["blocking"]
    assert_match(/keep one and reject the other/, signals["recommended_action"])
  end
end
