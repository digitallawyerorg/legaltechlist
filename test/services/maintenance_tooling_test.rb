require "test_helper"
require "minitest/mock"

# The five failures behind tonight's stalled approvals, each covered so the same wall
# cannot come back silently.
class MaintenanceToolingTest < ActiveSupport::TestCase
  GOOD = "Veronto builds an access-request and trade-secret workflow platform for law firms and in-house legal teams, hosted in the EU.".freeze

  setup do
    @admin = admin_users(:one)
    @company = companies(:one)
    @company.update!(name: "Veronto", main_url: "https://veronto.example", description: "An enrichment overwrote the original text.")
    @company.update_columns(quality_status: nil, quality_review: nil, fingerprint: @company.calculated_fingerprint)
    @context = { admin_user: @admin }
  end

  # A tag whose stored name is already the canonical form, so the vocabulary lookup
  # resolves to it rather than to whatever an alias would redirect to.
  def canonical_tag
    @canonical_tag ||= begin
      name = TagNormalizationService.canonical_name("privacy")
      Tag.find_by("LOWER(name) = ?", name) || Tag.create!(name: name)
    end
  end

  def call_tool(tool, **args)
    JSON.parse(tool.call(server_context: @context, **args).to_h[:content].first[:text])
  end

  def proposal(status: "pending", reviewed_at: nil, company: nil)
    changes = { "name" => "Veronto", "main_url" => "https://veronto.example", "description" => GOOD }
    CompanyProposal.create!(
      status: status, proposal_type: "user_contribution", source: "user_contribution",
      source_identifier: SecureRandom.uuid, source_payload: {},
      proposed_changes: changes, final_changes: changes, duplicate_signals: {},
      reviewed_at: reviewed_at, company: company
    )
  end

  # ---- 1. a description is repairable without engineering -----------------

  test "a company description can be restored, with a reason and its previous value kept" do
    result = call_tool(Mcp::Tools::UpdateCompanyFieldTool, slug: @company.slug,
                       fields: { "description" => GOOD },
                       reason: "Restoring the submitter's original text after an enrichment overwrote it.")

    assert_equal GOOD, @company.reload.description
    edit = @company.quality_review["field_edits"].last
    assert_equal "Restoring the submitter's original text after an enrichment overwrote it.", edit["reason"]
    assert_equal "An enrichment overwrote the original text.", edit["changes"]["description"]["from"]
    refute_equal "blocked", result["result"]
  end

  test "restoring a description requires a reason and refuses text that fails the gate" do
    no_reason = call_tool(Mcp::Tools::UpdateCompanyFieldTool, slug: @company.slug, fields: { "description" => GOOD })
    assert_equal "blocked", no_reason["result"]
    assert_match(/requires a `reason`/, no_reason["error"])

    promotional = call_tool(Mcp::Tools::UpdateCompanyFieldTool, slug: @company.slug,
                            fields: { "description" => "Veronto is the leading best-in-class legal platform." }, reason: "test")
    assert_equal "blocked", promotional["result"]
    assert_match(/publication gate/, promotional["error"])
    refute_equal GOOD, @company.reload.description
  end

  test "a broken website can be corrected in place" do
    call_tool(Mcp::Tools::UpdateCompanyFieldTool, slug: @company.slug,
              fields: { "main_url" => "https://veronto.de" }, reason: "Site moved; the old domain 404s.")

    assert_equal "https://veronto.de", @company.reload.main_url
    assert_equal "veronto.de", @company.canonical_domain, "the dedup key follows the url"
  end

  # ---- 1b. success is confirmed, not echoed -------------------------------

  # The tool used to return the values it had been asked to write. That is an echo of
  # the request, not evidence the database accepted it — which is exactly how an agent
  # comes away believing it fixed a record it did not touch.
  test "a successful write reports values read back from the record, not the ones requested" do
    result = call_tool(Mcp::Tools::UpdateCompanyFieldTool, slug: @company.slug,
                       fields: { "city" => "Munich" }, reason: "Correcting the city.")

    assert_equal "updated", result["result"]
    assert_equal "Munich", result["confirmed"]["city"]
    assert_empty result["unconfirmed"]
    assert_equal @company.reload.city, result["confirmed"]["city"]
  end

  test "a value the record did not keep is reported as unsaved rather than as success" do
    result = call_tool(Mcp::Tools::UpdateCompanyFieldTool, slug: @company.slug,
                       fields: { "all_tags" => "not-a-real-tag-in-the-vocabulary" }, reason: "Testing a rejected tag.")

    refute_equal "updated", result["result"], "a tag the vocabulary refused is not a saved tag"
    assert result["unconfirmed"]["all_tags"].present?
    assert_match(/reported success, but/, result["error"])
    assert_equal "not-a-real-tag-in-the-vocabulary", result["unconfirmed"]["all_tags"]["requested"]
  end

  test "a multi-field write says which field failed instead of failing flat" do
    result = call_tool(Mcp::Tools::UpdateCompanyFieldTool, slug: @company.slug,
                       fields: { "city" => "Munich", "all_tags" => "not-a-real-tag-in-the-vocabulary" },
                       reason: "One good field and one the vocabulary will refuse.")

    assert_equal "partially_updated", result["result"]
    assert_equal "Munich", result["confirmed"]["city"]
    assert_includes result["unconfirmed"].keys, "all_tags"
    assert_equal "Munich", @company.reload.city, "the field that did save stays saved"
  end

  test "the audit records what was confirmed, not what was asked for" do
    call_tool(Mcp::Tools::UpdateCompanyFieldTool, slug: @company.slug,
              fields: { "city" => "Munich", "all_tags" => "not-a-real-tag-in-the-vocabulary" },
              reason: "One good field and one the vocabulary will refuse.")

    run = PipelineRun.where(run_type: "curator_mcp").order(:created_at).last
    assert_equal "partially_updated", run.details["result"]
    assert_equal "Munich", run.details["confirmed"]["city"]
    assert_includes run.details["unconfirmed"].keys, "all_tags"
  end

  # ---- 2. a repair is not undone by the next enrichment -------------------

  test "writing a description locks the record against automated description changes" do
    call_tool(Mcp::Tools::UpdateCompanyFieldTool, slug: @company.slug, fields: { "description" => GOOD }, reason: "Restore.")
    assert @company.reload.quality_review["description_locked"]

    locked = proposal(company: @company)
    error = assert_raises(CompanyProposalEnrichmentService::Locked) do
      CompanyProposalEnrichmentService.call(proposal: locked, admin_user: @admin)
    end
    assert_match(/description is locked/, error.message)
  end

  # ---- 3. enrichment cannot rewrite what a reviewer already read ----------

  test "enrichment refuses a record a human has reviewed or approved" do
    reviewed = proposal(reviewed_at: 1.minute.ago)
    assert_raises(CompanyProposalEnrichmentService::Locked) do
      CompanyProposalEnrichmentService.call(proposal: reviewed, admin_user: @admin)
    end

    approved = proposal(status: "approved_to_draft")
    error = assert_raises(CompanyProposalEnrichmentService::Locked) do
      CompanyProposalEnrichmentService.call(proposal: approved, admin_user: @admin)
    end
    assert_match(/already been approved/, error.message)
  end

  test "an explicit request still enriches, and the job records a skip rather than failing" do
    reviewed = proposal(reviewed_at: 1.minute.ago)
    assert_nothing_raised { CompanyProposalEnrichmentService.call(proposal: reviewed, admin_user: @admin, force: true) }

    skipped = proposal(reviewed_at: 1.minute.ago)
    EnrichProposalJob.perform_now(skipped.id, @admin.id)
    assert skipped.reload.agent_details["enrichment_skipped"].present?, "a skip is recorded, not raised"
  end

  # ---- 4. an approval record is not overwritten by a later action ---------

  test "returning a record to its contributor preserves who reviewed it" do
    approved_at = 2.hours.ago.change(usec: 0)
    @company.update_columns(human_reviewed_at: approved_at, quality_status: "needs_review")

    CompanyReviewMarkService.call(company: @company, decision: "return_to_contributor",
                                  admin_user: @admin, instructions: "Please supply a working URL.")

    assert_equal approved_at.to_i, @company.reload.human_reviewed_at.to_i, "the approval timestamp survives"
    assert_equal "awaiting_contributor", @company.review_state
  end

  # ---- 5. duplicate checks see hidden drafts -----------------------------

  test "duplicate_check finds an unpublished draft so a second approval cannot duplicate it" do
    @company.update_columns(visible: false)

    result = call_tool(Mcp::Tools::DuplicateCheckTool, name: "Veronto", url: "https://veronto.example")

    assert_equal "existing_or_possible_duplicate", result["status"]
    match = (result["name_matches"] + result["domain_matches"]).first
    assert_equal @company.id, match["id"]
    assert_equal false, match["visible"], "and the caller can tell it is only a draft"
  end

  # ---- 6. an unverified description may be published by hand, never by a machine ----

  def gated_proposal(verification)
    changes = {
      "name" => "Zephyr Privacy", "main_url" => "https://zephyrprivacy.example",
      "description" => "Zephyr Privacy builds anonymisation and redaction software for corporate legal teams and public authorities, deployed with EU hosting.",
      "location" => "Wiesbaden, Germany", "founded_date" => "2019",
      "category_id" => categories(:one).id,
      "business_model_id" => business_models(:one).id, "business_model_ids" => [business_models(:one).id],
      "target_client_id" => target_clients(:one).id, "target_client_ids" => [target_clients(:one).id]
    }
    CompanyProposal.create!(
      status: "ready_for_review", proposal_type: "discovery_candidate", source: "llm_discovery",
      source_identifier: SecureRandom.uuid, source_payload: {},
      proposed_changes: changes, final_changes: changes, duplicate_signals: {},
      enriched_at: Time.current,
      agent_details: researched_agent_details(url: "https://zephyrprivacy.example").merge("description_verification" => verification)
    )
  end

  test "a skipped verification leaves the record publishable by hand but not automatically" do
    report = CompanyProposalQualityService.call(gated_proposal("decision" => "SKIPPED", "accuracy_assessment" => "The verifier could not run."))

    assert report["publish_ready"], "a reviewer may still publish on their own judgement"
    refute report["description_verified"], "but nothing autonomous may"
    assert(report["warnings"].any? { |w| w.include?("has not been verified") })
  end

  test "an approved verification is the only thing that clears autonomous publication" do
    approved = CompanyProposalQualityService.call(gated_proposal("decision" => "APPROVE"))
    assert approved["description_verified"]
    refute(approved["warnings"].any? { |w| w.include?("has not been verified") })

    revised = CompanyProposalQualityService.call(gated_proposal("decision" => "REVISE"))
    refute revised["description_verified"], "a revision is not a pass"
  end

  # ---- 7. approval refuses text the reviewer never read ------------------

  test "an approval is refused when the description changed after it was rendered" do
    record = gated_proposal("decision" => "APPROVE")
    stale = CompanyProposalApprovalService.digest_for(record.final_changes["description"])
    record.update!(final_changes: record.final_changes.merge("description" => "An enrichment replaced this text mid-review, dropping every named customer type."))

    error = assert_raises(ArgumentError) do
      CompanyProposalApprovalService.call(proposal: record, admin_user: @admin, publish: false, reviewed_description_digest: stale)
    end
    assert_match(/description changed after you opened this record/, error.message)
    assert_nil record.reload.company_id, "nothing was created from text nobody read"
  end

  test "an approval proceeds when the text is unchanged" do
    record = gated_proposal("decision" => "APPROVE")
    digest = CompanyProposalApprovalService.digest_for(record.final_changes["description"])

    company = CompanyProposalApprovalService.call(proposal: record, admin_user: @admin, publish: false, reviewed_description_digest: digest)
    assert company.persisted?
  end

  # ---- 8. the auto-apply path obeys the same rules ----------------------

  test "applying a user suggestion cannot overwrite a locked description" do
    @company.update_columns(quality_review: { "description_locked" => true })
    suggestion = CompanyProposal.create!(
      status: "ready_for_review", proposal_type: "user_suggestion", source: "user_suggestion",
      source_identifier: SecureRandom.uuid, source_payload: {}, company: @company,
      proposed_changes: {}, final_changes: { "description" => "Replacement text from a suggestion that should not land." },
      duplicate_signals: {}
    )

    error = assert_raises(ArgumentError) do
      CompanyProposalApplyUpdateService.call(proposal: suggestion, admin_user: @admin)
    end
    assert_match(/locked against automated changes/, error.message)
    refute_equal "Replacement text from a suggestion that should not land.", @company.reload.description
  end

  test "a permitted suggestion records what it replaced and why" do
    replacement = "Veronto develops privacy and compliance software for corporate legal teams, public authorities and law firms."
    suggestion = CompanyProposal.create!(
      status: "ready_for_review", proposal_type: "user_suggestion", source: "user_suggestion",
      source_identifier: SecureRandom.uuid, source_payload: {}, company: @company,
      proposed_changes: {}, final_changes: { "description" => replacement }, duplicate_signals: {}
    )
    previous = @company.description

    CompanyProposalApplyUpdateService.call(proposal: suggestion, admin_user: @admin)

    edit = @company.reload.quality_review["field_edits"].last
    assert_equal previous, edit["changes"]["description"]["from"]
    assert_equal "apply_user_suggestion", edit["via"]
  end

  # ---- 9. taxonomy an enrichment got wrong is now reachable -------------

  test "tags in the vocabulary are applied and a wrong secondary category can be cleared" do
    @company.update_columns(secondary_category_id: categories(:two).id)
    known = canonical_tag.name

    result = call_tool(Mcp::Tools::UpdateCompanyFieldTool, slug: @company.slug,
                       fields: { "all_tags" => known, "secondary_category_id" => nil },
                       reason: "An enrichment set a secondary category that does not apply.")

    @company.reload
    assert_nil @company.secondary_category_id, "a wrong secondary category can be cleared"
    assert_includes @company.tags.map(&:name), known
    assert_empty result["rejected_tags"]
  end

  # The vocabulary is closed. A name outside it used to be created as a new tag, or
  # folded into a different one by an alias, with no way to tell either had happened.
  test "a tag outside the vocabulary is reported rather than invented" do
    result = call_tool(Mcp::Tools::UpdateCompanyFieldTool, slug: @company.slug,
                       fields: { "all_tags" => "#{canonical_tag.name}, not-a-real-vocabulary-tag" },
                       reason: "Correcting tags after an enrichment.")

    assert_includes result["rejected_tags"], "not-a-real-vocabulary-tag"
    assert_match(/controlled vocabulary/, result["rejected_tags_note"])
    refute_includes @company.reload.tags.map(&:name), "not-a-real-vocabulary-tag"
    assert_equal 0, Tag.where(name: "not-a-real-vocabulary-tag").count, "and no tag was minted"
  end
end
