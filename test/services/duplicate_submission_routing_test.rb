require "test_helper"

# A submission for a company the index already holds goes to duplicate resolution, not
# through the normal review flow. Every case here is a real one: the queue's own history
# is that these were rejected in the same second they arrived, enriched over before anyone
# read them, or drafted as new work beside the entry they duplicated.
class DuplicateSubmissionRoutingTest < ActiveSupport::TestCase
  setup do
    @company = companies(:one)
    @company.update_columns(quality_status: nil, visible: true)
  end

  def published!(name:, url:, **columns)
    @company.update!(name: name, main_url: url)
    @company.update_columns({ canonical_domain: Company.canonical_domain_for(url), visible: true, quality_status: nil }.merge(columns))
    @company
  end

  def contribution(name:, url:, description: "Contract workflow software for in-house legal teams.", **changes)
    proposed = { "name" => name, "main_url" => url, "description" => description }.merge(changes)
    CompanyProposal.create!(
      status: "pending",
      proposal_type: "user_contribution",
      source: "user_contribution",
      source_identifier: SecureRandom.uuid,
      submitter_email: "founder@example.org",
      source_payload: {},
      proposed_changes: proposed,
      final_changes: proposed
    )
  end

  def process!(proposal)
    CompanyUserSubmissionProcessorService.call(proposal: proposal).tap { proposal.reload }
  end

  # Notaron 4167 duplicated public company 14904 on domain, name, LinkedIn and Crunchbase
  # at once, and was auto-rejected in the same second it arrived — so the comparison its
  # own blocker asked for was never possible.
  test "a submission matching a published record is routed to resolution, not rejected" do
    published!(name: "Notaron", url: "https://notaron.com/")
    proposal = contribution(name: "Notaron", url: "https://notaron.com")

    result = process!(proposal)

    assert_equal "duplicate_resolution", result["status"]
    assert_equal "ready_for_review", proposal.status
    refute proposal.rejected?, "a duplicate is a comparison to make, not a submission to discard"
    assert proposal.duplicate_blocking?, "it has to appear in the reviewer's duplicate queue"
    assert_equal @company.id, proposal.agent_details.dig("duplicate_routing", "canonical_company_id")
    assert proposal.agent_details.dig("duplicate_routing", "canonical_company_visible")
    assert_match(/already in the index/, proposal.reviewer_notes)
  end

  # Nothing automated may touch a routed submission. An enrichment fired 28 to 304 seconds
  # before disposition on record after record, overwriting the submitted text.
  test "a routed submission is not enriched, drafted or published" do
    published!(name: "Notaron", url: "https://notaron.com/")
    proposal = contribution(name: "Notaron", url: "https://notaron.com")

    process!(proposal)

    assert_nil proposal.enriched_at, "enriching would overwrite the submitted text before anyone read it"
    assert_nil proposal.company_id, "no second row"
    assert_equal "Contract workflow software for in-house legal teams.", proposal.final_changes["description"]
  end

  # Deep-Law: the submission's brand is published by an entry named for something else, on
  # another TLD. Nothing flagged it, and it became a second hidden row.
  test "a submission for a brand published on another TLD is routed" do
    published!(name: "D-Developments", url: "https://deep-law.io")
    proposal = contribution(name: "Deep-Law", url: "https://deep-law.com")

    assert_equal "duplicate_resolution", process!(proposal)["status"]
    assert_equal "brand_name", proposal.current_duplicate_signals["name_matches"].first["match_type"]
  end

  # Hidden mints are what every recent approval produced, and a submission matching one
  # used to sail through because the domain rule only looked at publicly visible rows.
  test "a submission matching a hidden approved row is routed" do
    published!(name: "SpecterAI", url: "https://specterlaw.ai", visible: false)
    proposal = contribution(name: "SpecterAI", url: "https://specterlaw.ai")

    assert_equal "duplicate_resolution", process!(proposal)["status"]
    refute proposal.agent_details.dig("duplicate_routing", "canonical_company_visible"),
           "the reviewer has to know the canonical record is not public"
  end

  # Two proposals from one submission arrived 1, 21, 49 and 76 seconds apart, and one was
  # auto-applied and published five seconds later over a blocking duplicate.
  test "twin submissions from one double-post are routed rather than both processed" do
    published!(name: "Unrelated Public Entry", url: "https://unrelated-public-entry.example")
    first = contribution(name: "Europaius", url: "https://europaius.com")
    first.update!(status: "ready_for_review")
    second = contribution(name: "Europaius", url: "https://europaius.com")

    assert_equal "duplicate_resolution", process!(second)["status"]
    match = second.current_duplicate_signals["proposal_matches"].first
    assert_equal first.id, match["proposal_id"]
    assert match["is_older"]
    assert_match(/keep one and reject the other/, second.reviewer_notes)
  end

  # Spam is still spam, and it is disposed of before anything else looks at it.
  test "spam is still rejected outright" do
    proposal = contribution(name: "Spam Co", url: "https://spam-co.example", description: "Buy viagra cheap casino now")

    assert_equal "rejected", process!(proposal)["status"]
    assert_nil proposal.agent_details["duplicate_routing"]
  end

  # Contracts 365 against Cloud Contracts 365: two companies in two countries. A
  # submission like this has to reach the normal review flow.
  test "a genuinely new submission sharing a word with an entry is not routed" do
    published!(name: "Cloud Contracts 365", url: "https://www.cloudcontracts365.com/")
    proposal = contribution(name: "Contracts 365", url: "https://www.contracts365.com")

    result = process!(proposal)

    refute_equal "duplicate_resolution", result["status"]
    assert_nil proposal.agent_details["duplicate_routing"]
    refute proposal.duplicate_blocking?
  end

  # A suggestion is bound to its company, so matching that company is the record
  # commenting on itself. Rejecting those as "already published" answered a complaint
  # about a published row by restating that it is published.
  test "a suggestion against its own company is not treated as a duplicate of it" do
    published!(name: "Gaius-Lex", url: "https://gaius-lex.pl")
    proposal = CompanyProposal.create!(
      status: "pending",
      proposal_type: "user_suggestion",
      source: "user_suggestion",
      source_identifier: SecureRandom.uuid,
      company: @company,
      submitter_email: "owner@gaius-lex.pl",
      issue_type: "incorrect_details",
      user_message: "The description describes the wrong product entirely.",
      source_payload: {},
      proposed_changes: { "name" => "Gaius-Lex", "main_url" => "https://gaius-lex.pl" },
      final_changes: { "name" => "Gaius-Lex", "main_url" => "https://gaius-lex.pl" }
    )

    refute_equal "duplicate_resolution", process!(proposal)["status"]
    refute proposal.duplicate_blocking?
    refute proposal.rejected?
  end

  # ---- the evidence has to outlive the live view --------------------------

  # Proposal 4175 carried a blocking match naming its twin 4174. After 4174 was rejected,
  # 4175 read clean and empty: the remediation erased the evidence of the defect it
  # remediated, and a later reader concludes the auto-apply ran on an uncontested row.
  test "blocking evidence survives the matched record changing state" do
    published!(name: "Unrelated Public Entry", url: "https://unrelated-public-entry.example")
    twin = contribution(name: "Caseway", url: "https://caseway.ai")
    twin.update!(status: "ready_for_review")
    proposal = contribution(name: "Caseway", url: "https://caseway.ai")

    assert proposal.refresh_duplicate_signals!["blocking"]
    twin.update!(status: "rejected")

    refute CompanyProposal.find(proposal.id).duplicate_blocking?,
           "the live view correctly stops blocking once the twin is resolved"
    evidence = proposal.reload.duplicate_evidence
    assert_equal 1, evidence.size
    assert_equal twin.id, evidence.first["matched"].first["proposal_id"]
    assert evidence.first["first_seen_at"].present?
  end

  test "evidence is appended once per distinct match, not on every read" do
    published!(name: "Notaron", url: "https://notaron.com/")
    proposal = contribution(name: "Notaron", url: "https://notaron.com")

    3.times { proposal.refresh_duplicate_signals! }

    assert_equal 1, proposal.reload.duplicate_evidence.size
  end

  test "a submission with no match records no evidence" do
    published!(name: "Unrelated Public Entry", url: "https://unrelated-public-entry.example")
    proposal = contribution(name: "Wholly Novel Filing Co", url: "https://whollynovelfiling.example")

    proposal.refresh_duplicate_signals!

    assert_empty proposal.reload.duplicate_evidence
  end

  # ---- the stored snapshot written at intake ------------------------------

  # The stored signals carried "Review duplicate domain before approval." whenever the
  # submission had a URL at all, against empty match arrays, which is how reviewers
  # learned to read them as noise.
  test "intake signals say nothing when nothing matched" do
    published!(name: "Unrelated Public Entry", url: "https://unrelated-public-entry.example")
    proposal = UserContributionIntakeService.call(form: contribution_form(name: "Wholly Novel Filing Co", main_url: "https://whollynovelfiling.example"))

    assert_empty proposal.duplicate_signals["name_matches"]
    assert_empty proposal.duplicate_signals["domain_matches"]
    refute proposal.duplicate_signals["blocking"]
    assert_nil proposal.duplicate_signals["recommended_action"]
  end

  test "intake signals name the match when there is one" do
    published!(name: "Notaron", url: "https://notaron.com/")
    proposal = UserContributionIntakeService.call(form: contribution_form(name: "Notaron", main_url: "https://notaron.com"))

    assert proposal.duplicate_signals["blocking"]
    assert_equal [@company.id], proposal.duplicate_signals["domain_matches"].map { |match| match["id"] }
  end

  # The path that reopens a record past the processor. A reviewer returns a submission,
  # the company is published from somewhere else while the contributor is writing their
  # answer, and the answer arrives naming a record that now exists. The reopen sets the
  # row to "ready_for_review", and the processor only ever touches "pending" — so before
  # the gate was asked here, this landed in the normal review queue with nothing on it
  # saying which published record it duplicated.
  test "a resubmission that now matches a published record is routed to resolution" do
    published!(name: "Unrelated Public Entry", url: "https://unrelated-public-entry.example")
    original = UserContributionIntakeService.call(form: contribution_form(name: "Notaron", main_url: "https://notaron.com"))
    refute original.duplicate_signals["blocking"], "nothing matched when it was first submitted"

    CompanyProposalReturnService.call(
      proposal: original, admin_user: admin_users(:one),
      instructions: "The description does not say what the product does.", fields: %w[description]
    )
    published!(name: "Notaron", url: "https://notaron.com/")

    again = UserContributionIntakeService.call(form: contribution_form(name: "Notaron", main_url: "https://notaron.com"))

    assert_equal original.id, again.id, "the answer lands on the row that was returned"
    again.reload
    assert again.duplicate_blocking?, "the duplicate queue has to show it"
    assert_equal @company.id, again.agent_details.dig("duplicate_routing", "canonical_company_id"),
                 "the reopen has to pass through the gate, not around it"
    assert_match(/already in the index/, again.reviewer_notes)
    assert_nil again.company_id, "routing publishes nothing"
  end

  # reviewed_at says when a human last looked at the record, and the reopen keeps the one
  # the reviewer earned on purpose. Routing must not overwrite it with the machine's own
  # clock, or the reopen's promise is undone by the gate it now calls.
  test "routing a resubmission keeps the reviewer's own reviewed_at" do
    published!(name: "Unrelated Public Entry", url: "https://unrelated-public-entry.example")
    original = UserContributionIntakeService.call(form: contribution_form(name: "Notaron", main_url: "https://notaron.com"))

    CompanyProposalReturnService.call(
      proposal: original, admin_user: admin_users(:one),
      instructions: "The description does not say what the product does.", fields: %w[description]
    )
    reviewed_at = Time.zone.local(2026, 3, 4, 9, 30, 0)
    original.update_columns(reviewed_at: reviewed_at)
    published!(name: "Notaron", url: "https://notaron.com/")

    again = UserContributionIntakeService.call(form: contribution_form(name: "Notaron", main_url: "https://notaron.com")).reload

    assert again.agent_details["duplicate_routing"].present?, "the gate ran on this path"
    assert_equal reviewed_at.to_i, again.reviewed_at.to_i,
                 "the gate stamped over the timestamp a human earned"
  end

  private

  def contribution_form(name:, main_url:)
    CompanyContributionForm.new(
      contact_email: "contributor@example.org",
      contact_name: "Ada Contributor",
      name: name,
      main_url: main_url,
      location: "Palo Alto, CA",
      founded_date: "2024",
      category_id: categories(:one).id,
      description: "Contract workflow software for in-house teams.",
      status: "active",
      business_model_ids: [business_models(:one).id],
      target_client_ids: [target_clients(:one).id],
      tag_names: ["artificial intelligence"]
    )
  end
end
