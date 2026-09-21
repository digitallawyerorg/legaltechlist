require "test_helper"
require "minitest/mock"

module Mcp
  class CuratorToolsTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @curator = AdminUser.find_or_create_by!(email: Mcp::CuratorActor.email) do |user|
        user.password = "password123"
        user.password_confirmation = "password123"
      end
      @context = { actor: "test" }
    end

    test "search_companies returns visible companies with quality signals" do
      result = call(Mcp::Tools::SearchCompaniesTool, query: "Test Company")
      names = result["companies"].map { |company| company["name"] }
      assert_includes names, "Test Company One"
      assert result["companies"].first.key?("quality_status")
    end

    test "get_company returns a full profile by slug" do
      result = call(Mcp::Tools::GetCompanyTool, slug: "test-company-one")
      assert_equal "Test Company One", result["name"]
      assert result.key?("revenue_models")
      assert result.key?("duplicate_domain_matches")
    end

    test "get_company reports missing companies as an error" do
      response = Mcp::Tools::GetCompanyTool.call(server_context: @context, slug: "does-not-exist")
      assert response.error?
    end

    test "get_company surfaces founded_date backfill provenance and status" do
      companies(:one).update_columns(founded_date: "", founded_year_provenance: { "status" => "no_source", "attempted_at" => 1.day.ago.utc.iso8601 })
      result = call(Mcp::Tools::GetCompanyTool, slug: "test-company-one")
      assert_equal "no_source", result["founded_year_provenance"]["status"]
      assert_equal "no_source", result["founded_date_backfill_status"]
    end

    test "get_company reports untried companies with no backfill marker" do
      companies(:one).update_columns(founded_date: "", founded_year_provenance: nil)
      result = call(Mcp::Tools::GetCompanyTool, slug: "test-company-one")
      assert_equal "untried", result["founded_date_backfill_status"]
    end

    test "duplicate_check flags an existing canonical domain" do
      result = call(Mcp::Tools::DuplicateCheckTool, name: "Brand New Co", url: "http://example.com")
      assert_equal "existing_or_possible_duplicate", result["status"]
      assert result["domain_matches"].any?
    end

    test "assess_proposal is read only and reports the quality gate" do
      proposal = pending_proposal
      assert_no_difference "Company.count" do
        result = call(Mcp::Tools::AssessProposalTool, id: proposal.id)
        assert_equal false, result["publish_ready"]
        assert result["quality"]["blockers"].any?
      end
    end

    test "approve_proposal blocks publishing when the quality gate fails" do
      proposal = pending_proposal
      response = Mcp::Tools::ApproveProposalTool.call(server_context: @context, id: proposal.id, publish: true)
      assert response.error?
      assert_equal "pending", proposal.reload.status
    end

    test "approve_proposal creates an invisible draft without publishing" do
      proposal = ready_proposal
      assert_difference "Company.count", 1 do
        result = call(Mcp::Tools::ApproveProposalTool, id: proposal.id, publish: false)
        assert_equal false, result["published"]
      end
      assert_equal "approved_to_draft", proposal.reload.status
      assert_not proposal.company.visible?
    end

    test "reject_proposal marks the proposal rejected and writes an audit run" do
      proposal = pending_proposal
      assert_difference -> { PipelineRun.where(run_type: "curator_mcp").count }, 1 do
        call(Mcp::Tools::RejectProposalTool, id: proposal.id, reason: "Out of scope")
      end
      assert_equal "rejected", proposal.reload.status
      assert_equal "Out of scope", proposal.rejection_reason
      assert_equal @curator, proposal.admin_user
    end

    test "apply_safe_fields only writes allowlisted fields" do
      company = companies(:one)
      call(Mcp::Tools::ApplySafeFieldsTool, slug: company.slug, fields: { "quality_status" => "verified", "name" => "HACKED" })
      company.reload
      assert_equal "verified", company.quality_status
      assert_equal "Test Company One", company.name
    end

    test "mark_review reject hides the company" do
      company = companies(:two)
      call(Mcp::Tools::MarkReviewTool, slug: company.slug, decision: "reject")
      company.reload
      assert_equal "rejected", company.quality_status
      assert_not company.visible
    end

    test "get_taxonomy returns the controlled vocabulary" do
      result = call(Mcp::Tools::GetTaxonomyTool)
      assert result["categories"].is_a?(Array)
      assert result["tags"].is_a?(Array)
      category_ids = result["categories"].map { |entry| entry["id"] }
      assert_includes category_ids, categories(:one).id
    end

    test "update_proposal writes only allowlisted fields into final_changes" do
      proposal = pending_proposal
      result = call(Mcp::Tools::UpdateProposalTool, id: proposal.id, changes: { "description" => "Neutral legal-tech description.", "quality_status" => "verified" })
      proposal.reload
      assert_equal "Neutral legal-tech description.", proposal.final_changes["description"]
      assert_not proposal.final_changes.key?("quality_status")
      assert_includes result["updated_fields"], "description"
    end

    test "update_proposal rejects an empty change set" do
      proposal = pending_proposal
      response = Mcp::Tools::UpdateProposalTool.call(server_context: @context, id: proposal.id, changes: { "quality_status" => "verified" })
      assert response.error?
    end

    test "propose_company_update queues a proposal without touching the live company" do
      company = companies(:one)
      original_name = company.name
      assert_difference "CompanyProposal.count", 1 do
        result = call(Mcp::Tools::ProposeCompanyUpdateTool, slug: company.slug, changes: { "location" => "New City, CA" }, rationale: "Company relocated per their site.")
        assert_equal "ready_for_review", result["status"]
      end
      proposal = CompanyProposal.order(:created_at).last
      assert_equal "user_suggestion", proposal.proposal_type
      assert_equal company.id, proposal.company_id
      assert_equal @curator, proposal.admin_user
      assert_equal original_name, company.reload.name
    end

    test "approve_proposal applies an existing-company update only with human approval" do
      company = companies(:one)
      call(Mcp::Tools::ProposeCompanyUpdateTool, slug: company.slug, changes: { "location" => "Relocated City, CA" }, rationale: "Moved.")
      proposal = CompanyProposal.order(:created_at).last

      blocked = Mcp::Tools::ApproveProposalTool.call(server_context: @context, id: proposal.id)
      assert blocked.error?
      assert_not_equal "Relocated City, CA", company.reload.location

      call(Mcp::Tools::ApproveProposalTool, id: proposal.id, human_approved: true)
      assert_equal "Relocated City, CA", company.reload.location
      assert_equal "published", proposal.reload.status
    end

    # ---- duplicate detection holds every unattended path ------------------
    #
    # The queue owner's rule is that duplicate detection is a mandatory gate on every
    # ingestion path. publish defaults to human_approved, so an ordinary unattended
    # approve_proposal(id: X) arrives with publish == false, skips the publish gate that
    # reads holds_automation? entirely, and reaches DuplicateGate.enforce!, which refuses
    # only on blocking. An advisory duplicate therefore minted a hidden company draft
    # with no human anywhere in the loop.
    test "approve_proposal holds an unattended draft on an advisory duplicate" do
      advisory_neighbour!(name: "Ready", url: "https://ready-clm.example")
      proposal = ready_proposal

      assert_no_difference "Company.count" do
        response = Mcp::Tools::ApproveProposalTool.call(server_context: @context, id: proposal.id)
        assert response.error?
      end

      signals = proposal.reload.duplicate_signals
      refute signals["blocking"], "this is the advisory case, not the blocking one"
      assert signals["advisory"]
      assert_nil proposal.company_id, "nothing may be minted unattended over an advisory match"
    end

    test "a human approving past an advisory duplicate still drafts" do
      advisory_neighbour!(name: "Ready", url: "https://ready-clm.example")
      proposal = ready_proposal

      result = call(Mcp::Tools::ApproveProposalTool, id: proposal.id, human_approved: true, publish: false)

      assert_equal false, result["published"]
      assert proposal.reload.company_id.present?, "a human in the loop is exactly what advisory allows for"
    end

    # The other unattended path, and the worse one: a user suggestion applies onto a LIVE
    # company. The suggestion branch returned before DuplicateGate.check ever ran, so
    # holds_automation? was never asked on it at all.
    test "approve_proposal holds an autonomous suggestion on an advisory duplicate" do
      company = companies(:one)
      original = company.name
      advisory_neighbour!(name: "Vantoria", url: "https://vantoria-legal.example")
      call(Mcp::Tools::ProposeCompanyUpdateTool, slug: company.slug, changes: { "name" => "Vantoria Technologies" }, rationale: "Rebrand.")
      proposal = CompanyProposal.order(:created_at).last

      with_env("MCP_CURATOR_AUTOAPPLY_UPDATES" => "true", "MCP_CURATOR_MIN_CONFIDENCE" => "0.8") do
        response = Mcp::Tools::ApproveProposalTool.call(server_context: @context, id: proposal.id, confidence: 0.9)
        assert response.error?
      end

      assert_equal original, company.reload.name, "a live entry must not be overwritten unattended over an advisory match"
      assert proposal.reload.duplicate_signals["advisory"]
    end

    test "a human approving a suggestion past an advisory duplicate still applies it" do
      company = companies(:one)
      advisory_neighbour!(name: "Vantoria", url: "https://vantoria-legal.example")
      call(Mcp::Tools::ProposeCompanyUpdateTool, slug: company.slug, changes: { "name" => "Vantoria Technologies" }, rationale: "Rebrand.")
      proposal = CompanyProposal.order(:created_at).last

      call(Mcp::Tools::ApproveProposalTool, id: proposal.id, human_approved: true)

      assert_equal "Vantoria Technologies", company.reload.name
    end

    test "approve_proposal publishes autonomously with high confidence when autopublish is on" do
      proposal = ready_proposal
      with_env("MCP_CURATOR_AUTOPUBLISH" => "true", "MCP_CURATOR_MIN_CONFIDENCE" => "0.8") do
        result = call(Mcp::Tools::ApproveProposalTool, id: proposal.id, publish: true, confidence: 0.95)
        assert_equal true, result["published"]
      end
      assert_equal "published", proposal.reload.status
    end

    test "approve_proposal refuses autonomous publish below the confidence threshold" do
      proposal = ready_proposal
      with_env("MCP_CURATOR_AUTOPUBLISH" => "true", "MCP_CURATOR_MIN_CONFIDENCE" => "0.8") do
        response = Mcp::Tools::ApproveProposalTool.call(server_context: @context, id: proposal.id, publish: true, confidence: 0.4)
        assert response.error?
      end
      assert_equal "ready_for_review", proposal.reload.status
    end

    test "existing-company update applies autonomously when enabled and confident" do
      company = companies(:one)
      call(Mcp::Tools::ProposeCompanyUpdateTool, slug: company.slug, changes: { "location" => "Auto City, CA" }, rationale: "Verified.")
      proposal = CompanyProposal.order(:created_at).last
      with_env("MCP_CURATOR_AUTOAPPLY_UPDATES" => "true", "MCP_CURATOR_MIN_CONFIDENCE" => "0.8") do
        call(Mcp::Tools::ApproveProposalTool, id: proposal.id, confidence: 0.9)
      end
      assert_equal "Auto City, CA", company.reload.location
    end

    test "existing-company update stays blocked when autoapply is disabled even at high confidence" do
      company = companies(:one)
      original = company.location
      call(Mcp::Tools::ProposeCompanyUpdateTool, slug: company.slug, changes: { "location" => "Blocked City" }, rationale: "x")
      proposal = CompanyProposal.order(:created_at).last
      with_env("MCP_CURATOR_AUTOAPPLY_UPDATES" => "false") do
        response = Mcp::Tools::ApproveProposalTool.call(server_context: @context, id: proposal.id, confidence: 0.99)
        assert response.error?
      end
      assert_equal original, company.reload.location
    end

    test "external submissions auto-publish only above the higher external confidence bar" do
      proposal = ready_proposal
      proposal.update!(submitter_email: "founder@example.com")
      with_env("MCP_CURATOR_AUTOPUBLISH" => "true", "MCP_CURATOR_MIN_CONFIDENCE" => "0.8", "MCP_CURATOR_MIN_CONFIDENCE_EXTERNAL" => "0.9") do
        # 0.85 clears the normal bar but not the external bar
        blocked = Mcp::Tools::ApproveProposalTool.call(server_context: @context, id: proposal.id, publish: true, confidence: 0.85)
        assert blocked.error?
        assert_not_equal "published", proposal.reload.status
        # 0.95 clears the external bar
        call(Mcp::Tools::ApproveProposalTool, id: proposal.id, publish: true, confidence: 0.95)
      end
      assert_equal "published", proposal.reload.status
    end

    test "update_proposal confirming taxonomy clears the low-confidence taxonomy blocker" do
      proposal = ready_proposal
      proposal.update!(agent_details: proposal.agent_details.merge("taxonomy_suggestion" => { "accepted" => false }))
      before = CompanyProposalQualityService.call(proposal.reload)
      assert_not before["publish_ready"], before["blockers"].inspect
      assert before["blockers"].any? { |blocker| blocker =~ /low-confidence taxonomy/i }, before["blockers"].inspect

      result = call(Mcp::Tools::UpdateProposalTool, id: proposal.id, changes: { "category_id" => categories(:one).id })
      assert result["taxonomy_confirmed"]
      assert result["quality"]["publish_ready"], result["quality"]["blockers"].inspect
    end

    test "list_review_queue pages through the backlog with offset and total" do
      3.times { pending_proposal }
      page1 = call(Mcp::Tools::ListReviewQueueTool, status: "pending", limit: 2, offset: 0)
      page2 = call(Mcp::Tools::ListReviewQueueTool, status: "pending", limit: 2, offset: 2)
      assert page1["total"] >= 3
      assert_equal 2, page1["count"]
      assert page1["has_more"]
      first_ids = page1["proposals"].map { |entry| entry["id"] }
      second_ids = page2["proposals"].map { |entry| entry["id"] }
      assert (first_ids & second_ids).empty?, "pages should not overlap"
    end

    test "externally submitted spam is flagged as not publish-ready" do
      proposal = ready_proposal
      proposal.update!(
        submitter_email: "scammer@example.com",
        user_message: "Earn a salary of $5000 weekly, email mailto:agent@scam.org to apply.",
        final_changes: proposal.final_changes.merge("founded_date" => "ROHTO Pharmaceutical", "main_url" => "junk value")
      )
      quality = CompanyProposalQualityService.call(proposal)
      assert_not quality["publish_ready"]
      assert quality["blockers"].any? { |blocker| blocker =~ /spam|malformed/i }, quality["blockers"].inspect
    end

    test "internal discovery candidates are never flagged by the spam pre-gate" do
      proposal = ready_proposal
      proposal.update!(final_changes: proposal.final_changes.merge("description" => "Recruiting law firms; salary details on request. Contact via mailto:sales@co.com."))
      quality = CompanyProposalQualityService.call(proposal)
      assert_not quality["blockers"].any? { |blocker| blocker =~ /spam/i }, "spam gate must not touch internal candidates"
    end

    test "founding year is optional and does not block publishing" do
      proposal = ready_proposal
      proposal.update!(final_changes: proposal.final_changes.except("founded_date"))
      quality = CompanyProposalQualityService.call(proposal)
      assert quality["publish_ready"], quality["blockers"].inspect
      assert quality["warnings"].any? { |warning| warning =~ /founding year/i }

      with_env("MCP_CURATOR_AUTOPUBLISH" => "true", "MCP_CURATOR_MIN_CONFIDENCE" => "0.8") do
        result = call(Mcp::Tools::ApproveProposalTool, id: proposal.id, publish: true, confidence: 0.95)
        assert_equal true, result["published"]
        assert_equal "published", result["result"]
      end
      company = proposal.reload.company
      assert company.persisted?
      assert company.founded_date.blank?
      assert company.visible?
    end

    test "a genuinely missing required field still blocks while founded_date does not" do
      proposal = ready_proposal
      proposal.update!(final_changes: proposal.final_changes.except("founded_date", "description"))
      quality = CompanyProposalQualityService.call(proposal)
      assert_not quality["publish_ready"]
      assert_includes quality["missing_publish_blocking_fields"], "description"
      assert_not_includes quality["missing_publish_blocking_fields"], "founded_date"
    end

    test "update_proposal echoes persisted state and publish readiness" do
      proposal = pending_proposal
      result = call(Mcp::Tools::UpdateProposalTool, id: proposal.id, changes: { "description" => "Neutral legal-tech directory description for testing purposes." })
      assert_equal "updated", result["result"]
      assert_equal "Neutral legal-tech directory description for testing purposes.", result["persisted_changes"]["description"]
      assert result.key?("publish_ready")
      assert result.key?("blockers")
    end

    test "enrich_proposal queues async enrichment and returns a poll contract" do
      proposal = pending_proposal
      assert_enqueued_with(job: EnrichProposalJob, args: [proposal.id, @curator.id, { force: false }]) do
        result = call(Mcp::Tools::EnrichProposalTool, id: proposal.id)
        assert_equal "enrichment_queued", result["result"]
        assert result["poll"].present?
      end
    end

    test "get_proposal surfaces enrichment state for polling" do
      proposal = pending_proposal
      result = call(Mcp::Tools::GetProposalTool, id: proposal.id)
      assert result.key?("enriched_at")
      assert result.key?("enrichment_error")
    end

    test "EnrichProposalJob enriches the proposal off the request thread" do
      proposal = pending_proposal
      EnrichProposalJob.perform_now(proposal.id, @curator.id)
      assert proposal.reload.enriched_at.present?
    end

    test "sourced_year accepts a plausible year cited by gathered evidence" do
      year = CompanyProposalEnrichmentService.sourced_year(year: "2015", source: "https://www.techcrunch.com/article", allowed_hosts: ["techcrunch.com"])
      assert_equal "2015", year
    end

    test "sourced_year rejects an uncited or implausible year" do
      assert_nil CompanyProposalEnrichmentService.sourced_year(year: "2015", source: "https://random-blog.example/x", allowed_hosts: ["techcrunch.com"])
      assert_nil CompanyProposalEnrichmentService.sourced_year(year: "1200", source: "https://techcrunch.com", allowed_hosts: ["techcrunch.com"])
      assert_nil CompanyProposalEnrichmentService.sourced_year(year: "not a year", source: "https://techcrunch.com", allowed_hosts: ["techcrunch.com"])
      assert_nil CompanyProposalEnrichmentService.sourced_year(year: "2015", source: "", allowed_hosts: ["techcrunch.com"])
    end

    test "approve_proposal is idempotent and never mints a second company" do
      proposal = ready_proposal
      with_env("MCP_CURATOR_AUTOPUBLISH" => "true", "MCP_CURATOR_MIN_CONFIDENCE" => "0.8") do
        first = call(Mcp::Tools::ApproveProposalTool, id: proposal.id, publish: true, confidence: 0.95)
        assert_equal true, first["published"]
        company_id = first["company_id"]
        assert_no_difference "Company.count" do
          again = call(Mcp::Tools::ApproveProposalTool, id: proposal.id, publish: true, confidence: 0.95)
          assert_equal "already_published", again["result"]
          assert_equal true, again["published"]
          assert_equal company_id, again["company_id"]
        end
      end
    end

    test "approve_proposal publish=true promotes an existing invisible draft to visible" do
      proposal = ready_proposal
      with_env("MCP_CURATOR_AUTOPUBLISH" => "true", "MCP_CURATOR_MIN_CONFIDENCE" => "0.8") do
        drafted = call(Mcp::Tools::ApproveProposalTool, id: proposal.id, publish: false)
        assert_equal false, drafted["published"]
        company_id = drafted["company_id"]

        assert_no_difference "Company.count" do
          promoted = call(Mcp::Tools::ApproveProposalTool, id: proposal.id, publish: true, confidence: 0.95)
          assert_equal "published", promoted["result"]
          assert_equal true, promoted["published"]
          assert_equal company_id, promoted["company_id"]
        end
      end
      assert proposal.reload.company.visible?
      assert_equal "published", proposal.status
    end

    test "approve_proposal defaults to publishing when human_approved is passed" do
      proposal = ready_proposal
      result = call(Mcp::Tools::ApproveProposalTool, id: proposal.id, human_approved: true)
      assert_equal true, result["published"]
      assert_equal "published", result["result"]
      assert proposal.reload.company.visible?
    end

    test "approve_proposal still drafts when publish is explicitly false even with human approval" do
      proposal = ready_proposal
      result = call(Mcp::Tools::ApproveProposalTool, id: proposal.id, human_approved: true, publish: false)
      assert_equal false, result["published"]
      assert_not proposal.reload.company.visible?
    end

    test "update_company_field sets a factual field on a live company" do
      company = companies(:one)
      result = call(Mcp::Tools::UpdateCompanyFieldTool, slug: company.slug, fields: { "location" => "Austin, TX" })
      assert_equal "updated", result["result"]
      assert_equal "Austin, TX", company.reload.location
    end

    test "update_company_field requires a citation and a valid year for founded_date" do
      company = companies(:one)
      missing_cite = Mcp::Tools::UpdateCompanyFieldTool.call(server_context: @context, slug: company.slug, fields: { "founded_date" => "2018" })
      assert missing_cite.error?
      bad_year = Mcp::Tools::UpdateCompanyFieldTool.call(server_context: @context, slug: company.slug, fields: { "founded_date" => "not-a-year" }, source_url: "https://example.com")
      assert bad_year.error?
      ok = call(Mcp::Tools::UpdateCompanyFieldTool, slug: company.slug, fields: { "founded_date" => "2018" }, source_url: "https://example.com/about")
      assert_equal "updated", ok["result"]
      assert_equal "2018", company.reload.founded_date
    end

    test "enrich_proposal skips items that are already publishable" do
      proposal = ready_proposal
      assert_no_enqueued_jobs only: EnrichProposalJob do
        result = call(Mcp::Tools::EnrichProposalTool, id: proposal.id)
        assert_equal "skipped_already_publishable", result["result"]
      end
    end

    test "enrich_proposal skips recently-enriched items unless forced" do
      proposal = pending_proposal
      proposal.update!(enriched_at: 1.hour.ago)
      result = call(Mcp::Tools::EnrichProposalTool, id: proposal.id)
      assert_equal "skipped_recently_enriched", result["result"]
      assert_enqueued_with(job: EnrichProposalJob) do
        forced = call(Mcp::Tools::EnrichProposalTool, id: proposal.id, force: true)
        assert_equal "enrichment_queued", forced["result"]
      end
    end

    test "discover_companies enqueues an async run and returns a run id to poll" do
      assert_enqueued_with(job: CompanyDiscoveryJob) do
        result = call(Mcp::Tools::DiscoverCompaniesTool, discovery_type: "country", seed: "France")
        assert_equal "discovery_queued", result["result"]
        assert result["run_id"].present?
        assert_equal "pending", result["status"]
        assert_match(/get_discovery_run/, result["poll"])
      end
    end

    test "discover_companies rejects an invalid discovery type without enqueuing" do
      assert_no_enqueued_jobs(only: CompanyDiscoveryJob) do
        response = Mcp::Tools::DiscoverCompaniesTool.call(server_context: @context, discovery_type: "nonsense")
        assert response.error?
      end
    end

    test "get_discovery_run reports pending and then succeeded results" do
      run = PipelineRun.create!(name: "Company discovery: France", run_type: CompanyDiscoveryService::RUN_TYPE, status: "pending", agent_name: "CompanyDiscoveryService")
      pending = call(Mcp::Tools::GetDiscoveryRunTool, run_id: run.id)
      assert_equal "pending", pending["result"]

      run.update!(status: "succeeded", records_processed: 1, details: {
        "discovery_type" => "country",
        "summary" => { "discovered_count" => 2 },
        "proposal_results" => [{ "proposal_id" => 4242, "action" => "queued_for_review" }],
        "candidates" => [{ "name" => "Foo Legal", "website" => "https://foo.example", "status" => "absent_candidate" }]
      })
      done = call(Mcp::Tools::GetDiscoveryRunTool, run_id: run.id)
      assert_equal "succeeded", done["result"]
      assert_equal [4242], done["queued_proposal_ids"]
      assert_equal 1, done["queued_proposals_count"]
    end

    test "get_proposal surfaces the description critic verdict for a clean draft" do
      proposal = ready_proposal
      result = call(Mcp::Tools::GetProposalTool, id: proposal.id)
      assert_equal "pass", result["description_critic"]["verdict"]
    end

    test "get_proposal critic verdict reflects the live gate decision, not a stale stored verdict" do
      proposal = ready_proposal
      # Stored verdict says pass, but the current description is weak: get_proposal
      # must report the same 'revise' the publish gate acts on, not the stale value.
      proposal.update!(
        agent_details: proposal.agent_details.merge("description_critic" => { "verdict" => "pass", "issues" => [] }),
        final_changes: proposal.final_changes.merge(
          "description" => "BestProfi operates bestprofi.com as its primary web presence for publishing information and enabling online access to its services."
        )
      )
      result = call(Mcp::Tools::GetProposalTool, id: proposal.id)
      assert_equal "revise", result["description_critic"]["verdict"], result["description_critic"].inspect
      assert_equal false, result["quality"]["publish_ready"]
      assert_equal result["quality"]["description_critic"]["verdict"], result["description_critic"]["verdict"]
    end

    test "update_proposal refreshes the stored critic verdict when the description changes" do
      proposal = ready_proposal
      proposal.update!(agent_details: proposal.agent_details.merge("description_critic" => { "verdict" => "pass", "issues" => [] }))
      call(Mcp::Tools::UpdateProposalTool, id: proposal.id, changes: { "description" => "BestProfi operates bestprofi.com as its primary web presence for publishing information and enabling online access to its services." })
      assert_equal "revise", proposal.reload.agent_details["description_critic"]["verdict"]
    end

    test "list_review_queue computes publish_ready live when no cached report exists" do
      proposal = ready_proposal
      assert_nil proposal.cached_quality_report
      result = call(Mcp::Tools::ListReviewQueueTool, status: "ready_for_review")
      row = result["proposals"].find { |entry| entry["id"] == proposal.id }
      assert row, "expected the ready proposal in the queue"
      assert_not_nil row["publish_ready"]
    end

    test "get_stats returns directory and backlog counts" do
      result = call(Mcp::Tools::GetStatsTool)
      assert result["companies"].key?("total")
      assert result["companies"].key?("missing_founded_date")
      assert result["proposals"].key?("by_status")
      assert result["curator"].key?("min_confidence")
    end

    test "search_companies filters to companies missing a founded_date" do
      companies(:one).update_column(:founded_date, "2020")
      companies(:two).update_column(:founded_date, "")

      result = call(Mcp::Tools::SearchCompaniesTool, missing_founded_date: true)
      slugs = result["companies"].map { |company| company["slug"] }
      assert_includes slugs, "test-company-two"
      assert_not_includes slugs, "test-company-one"
    end

    test "backfill_founded_dates enqueues async backfills for blank-year companies" do
      companies(:one).update_column(:founded_date, "")
      assert_enqueued_with(job: BackfillFoundedDateJob) do
        result = call(Mcp::Tools::BackfillFoundedDatesTool, limit: 5)
        assert_equal "enqueued", result["result"]
        assert_operator result["enqueued"], :>=, 1
        assert_includes result["company_ids"], companies(:one).id
      end
    end

    test "backfill_founded_dates skips companies attempted within the cooldown on a blind run" do
      companies(:one).update_columns(founded_date: "", founded_year_provenance: { "status" => "no_source", "attempted_at" => 1.day.ago.utc.iso8601 })
      result = call(Mcp::Tools::BackfillFoundedDatesTool, limit: 50)
      assert_not_includes result["company_ids"], companies(:one).id
    end

    test "backfill_founded_dates targets specific company_ids and bypasses the cooldown" do
      companies(:one).update_columns(founded_date: "", founded_year_provenance: { "status" => "no_source", "attempted_at" => 1.day.ago.utc.iso8601 })
      result = call(Mcp::Tools::BackfillFoundedDatesTool, company_ids: [companies(:one).id])
      assert result["targeted"]
      assert_includes result["company_ids"], companies(:one).id
    end

    test "suggest_improvement records an audit run" do
      assert_difference -> { PipelineRun.where(run_type: "curator_mcp").count }, 1 do
        result = call(Mcp::Tools::SuggestImprovementTool, suggestion: "Add a bulk re-tagging tool.", area: "tooling")
        assert result["recorded"]
      end
    end

    test "record_acquisition sets status, acquirer, and exit date" do
      result = call(Mcp::Tools::RecordAcquisitionTool, slug: "test-company-one", acquirer_name: "LawVu", acquirer_url: "https://lawvu.com", acquired_on: "2025")
      assert_equal "recorded", result["result"]
      company = companies(:one).reload
      assert_equal "acquired", company.status
      assert_equal "LawVu", company.acquirer_name
      assert_equal "https://lawvu.com", company.acquirer_url
      assert_equal "2025-01-01", company.exit_date.iso8601
      assert_equal "LawVu", result["acquirer"]["name"]
    end

    test "record_acquisition links an in-index successor company" do
      result = call(Mcp::Tools::RecordAcquisitionTool, slug: "test-company-one", acquirer_name: "Test Company Two", successor_slug: "test-company-two")
      assert_equal "recorded", result["result"]
      assert_equal companies(:two).id, companies(:one).reload.successor_company_id
      assert_equal companies(:two).id, result["acquirer"]["successor_company_id"]
    end

    test "record_acquisition rejects a blank acquirer and self-succession" do
      blank = Mcp::Tools::RecordAcquisitionTool.call(server_context: @context, slug: "test-company-one", acquirer_name: "  ")
      assert blank.error?

      self_ref = Mcp::Tools::RecordAcquisitionTool.call(server_context: @context, slug: "test-company-one", acquirer_name: "X", successor_slug: "test-company-one")
      assert self_ref.error?
    end

    test "record_acquisition surfaces in get_company acquisition block" do
      call(Mcp::Tools::RecordAcquisitionTool, slug: "test-company-one", acquirer_name: "LawVu", acquirer_url: "https://lawvu.com")
      result = call(Mcp::Tools::GetCompanyTool, slug: "test-company-one")
      assert_equal "LawVu", result["acquisition"]["acquirer_name"]
      assert_equal "https://lawvu.com", result["acquisition"]["acquirer_url"]
    end

    test "record_acquisition records year precision and source url, surfaced in get_company" do
      result = call(Mcp::Tools::RecordAcquisitionTool, slug: "test-company-one", acquirer_name: "LawVu", acquired_on: "2024", source_url: "https://example.com/news")
      assert_equal "2024-01-01", result["acquired_on"]
      assert_equal "year", result["date_precision"]

      acq = call(Mcp::Tools::GetCompanyTool, slug: "test-company-one")["acquisition"]
      assert_equal "2024-01-01", acq["acquired_on"]
      assert_equal "year", acq["date_precision"]
      assert_equal "https://example.com/news", acq["source_url"]
    end

    test "approve_proposal publishes a historical company straight into acquired state" do
      proposal = ready_proposal
      result = call(Mcp::Tools::ApproveProposalTool, id: proposal.id, human_approved: true, status: "acquired",
                    acquisition: { "acquirer_name" => "BigLaw Corp", "acquirer_url" => "https://biglaw.example", "acquired_on" => "2023" })
      assert result["published"]
      assert_equal "acquired", result["company_status"]
      assert_equal "BigLaw Corp", result["acquisition"]["acquirer_name"]

      company = Company.find(result["company_id"])
      assert_equal "acquired", company.status
      assert company.visible?
      assert_equal "BigLaw Corp", company.acquirer_name
      assert_equal "2023-01-01", company.exit_date.iso8601
    end

    test "approve_proposal accepts a plain status without an acquisition payload" do
      proposal = ready_proposal
      result = call(Mcp::Tools::ApproveProposalTool, id: proposal.id, human_approved: true, status: "inactive")
      assert_equal "inactive", result["company_status"]
      assert_equal "inactive", Company.find(result["company_id"]).status
    end

    test "get_stats surfaces lifecycle counts and server version" do
      companies(:one).update_columns(status: "acquired")
      companies(:two).update_columns(status: "inactive")
      Rails.cache.clear
      result = call(Mcp::Tools::GetStatsTool)
      assert_equal Mcp::CuratorServer::VERSION, result["server_version"]
      assert result["companies"]["by_status"].is_a?(Hash)
      assert_operator result["companies"]["acquired"].to_i, :>=, 1
      assert_operator result["companies"]["inactive"].to_i, :>=, 1
    end

    test "create_company creates a pending proposal by default" do
      assert_no_difference "Company.count" do
        result = call(Mcp::Tools::CreateCompanyTool, name: "Brand New LegalCo", main_url: "https://brandnewlegalco.example")
        assert_equal "proposal_created", result["result"]
        assert result["created"]
        assert_equal false, result["published"]
        assert CompanyProposal.exists?(result["proposal_id"])
      end
    end

    test "create_company surfaces duplicate matches for an existing company" do
      result = call(Mcp::Tools::CreateCompanyTool, name: "Test Company One", main_url: "http://example.com")
      assert result["duplicate_matches"]["name"].any? || result["duplicate_matches"]["domain"].any?
    end

    test "create_company publishes a live company with human approval" do
      result = with_site_fetched("https://publishablelegalco.example") do
        call(Mcp::Tools::CreateCompanyTool,
             name: "Publishable LegalCo", main_url: "https://publishablelegalco.example",
             location: "Boston, MA", description: "Publishable LegalCo builds cloud-based contract review and analytics software used by corporate legal teams and law firms.",
             category_id: categories(:one).id, business_model_ids: [business_models(:one).id], target_client_ids: [target_clients(:one).id],
             publish: true, human_approved: true)
      end
      assert result["published"], result.inspect
      company = Company.find(result["company_id"])
      assert company.visible?
      assert_equal "Publishable LegalCo", company.name
    end

    test "create_company imports an acquired company in one call" do
      result = with_site_fetched("https://acquiredlegalco.example") do
        call(Mcp::Tools::CreateCompanyTool,
             name: "Acquired LegalCo", main_url: "https://acquiredlegalco.example",
             location: "Austin, TX", description: "Acquired LegalCo built litigation analytics and case management tools used by law firms and corporate legal departments.",
             category_id: categories(:one).id, business_model_ids: [business_models(:one).id], target_client_ids: [target_clients(:one).id],
             publish: true, human_approved: true,
             acquisition: { "acquirer_name" => "MegaLegal", "acquired_on" => "2022" })
      end
      assert result["published"]
      company = Company.find(result["company_id"])
      assert_equal "acquired", company.status
      assert_equal "MegaLegal", company.acquirer_name
      assert company.visible?
    end

    test "create_company will not publish a company whose site cannot be retrieved" do
      result = call(Mcp::Tools::CreateCompanyTool,
                    name: "Unreachable LegalCo", main_url: "https://unreachablelegalco.example",
                    location: "Boston, MA", description: "Unreachable LegalCo builds contract analytics software used by corporate legal teams and law firms.",
                    category_id: categories(:one).id, business_model_ids: [business_models(:one).id], target_client_ids: [target_clients(:one).id],
                    publish: true, human_approved: true)

      assert_equal "blocked", result["result"]
      assert_match(/No independently retrieved evidence/, result["error"])
      assert_nil result["company_id"]
    end

    test "create_company rejects an acquisition payload without publish" do
      response = Mcp::Tools::CreateCompanyTool.call(server_context: @context, name: "Draft Acq Co", main_url: "https://draftacqco.example", acquisition: { "acquirer_name" => "X" })
      assert response.error?
    end

    test "search_companies filters by lifecycle status" do
      companies(:one).update_columns(status: "acquired")
      companies(:two).update_columns(status: "active")
      result = call(Mcp::Tools::SearchCompaniesTool, status: "acquired")
      ids = result["companies"].map { |c| c["id"] }
      assert_includes ids, companies(:one).id
      assert_not_includes ids, companies(:two).id
    end

    test "check_url_health enqueues jobs for due companies" do
      companies(:one).update_columns(status: "active", main_url: "http://example.com", url_checked_at: nil)
      assert_enqueued_with(job: CheckCompanyUrlHealthJob) do
        result = call(Mcp::Tools::CheckUrlHealthTool, company_ids: [companies(:one).id])
        assert_equal "enqueued", result["result"]
        assert_includes result["company_ids"], companies(:one).id
      end
    end

    test "search_companies filters to broken urls" do
      companies(:one).update_columns(url_status: Company::URL_STATUS_BROKEN)
      result = call(Mcp::Tools::SearchCompaniesTool, url_broken: true)
      ids = result["companies"].map { |c| c["id"] }
      assert_includes ids, companies(:one).id
      assert_not_includes ids, companies(:two).id
    end

    test "get_company reports url_health status" do
      companies(:one).update_columns(url_status: Company::URL_STATUS_BROKEN, url_status_code: 404, url_checked_at: Time.current, url_health: { "consecutive_failures" => 2 })
      result = call(Mcp::Tools::GetCompanyTool, slug: "test-company-one")
      assert_equal Company::URL_STATUS_BROKEN, result["url_health"]["status"]
      assert_equal 2, result["url_health"]["consecutive_failures"]
    end

    test "get_stats exposes category/country/url_health/founded_date breakdowns" do
      Rails.cache.clear
      result = call(Mcp::Tools::GetStatsTool, fresh: true)
      companies = result["companies"]

      assert companies["by_category"].is_a?(Array)
      assert companies["by_category"].any? { |row| row["name"].present? && row.key?("visible_count") }
      assert companies["by_country"].is_a?(Array)
      assert companies["by_country"].any? { |row| row["country"] == "United States" }
      assert companies["url_health"].is_a?(Hash)
      %w[ok broken unknown untried].each { |key| assert companies["url_health"].key?(key) }
      assert companies["founded_date"].is_a?(Hash)
      %w[present null backfill_untried backfill_no_source].each { |key| assert companies["founded_date"].key?(key) }
    end

    test "get_stats reconciles inactive with by_status and reports closed separately" do
      companies(:one).update_columns(status: "inactive")
      companies(:two).update_columns(status: "closed")
      Rails.cache.clear
      result = call(Mcp::Tools::GetStatsTool, fresh: true)
      companies = result["companies"]

      assert_equal companies["by_status"]["inactive"].to_i, companies["inactive"]
      assert_equal companies["by_status"]["closed"].to_i, companies["closed"]
    end

    test "list_companies paginates and reports has_more" do
      page1 = call(Mcp::Tools::ListCompaniesTool, visible: true, limit: 1, offset: 0)
      assert_equal 1, page1["count"]
      assert page1["total"] >= 2
      assert page1["has_more"]
      page2 = call(Mcp::Tools::ListCompaniesTool, visible: true, limit: 1, offset: 1)
      assert (page1["companies"].map { |c| c["id"] } & page2["companies"].map { |c| c["id"] }).empty?
    end

    test "list_companies filters by category, missing founded_date, and country" do
      companies(:one).update_column(:founded_date, "")
      companies(:two).update_column(:founded_date, "2021")

      by_category = call(Mcp::Tools::ListCompaniesTool, category_id: 1)
      ids = by_category["companies"].map { |c| c["id"] }
      assert_includes ids, 1
      assert_not_includes ids, 2

      null_founded = call(Mcp::Tools::ListCompaniesTool, founded_date_null: true)
      assert_includes null_founded["companies"].map { |c| c["id"] }, 1
      assert_not_includes null_founded["companies"].map { |c| c["id"] }, 2

      swiss = call(Mcp::Tools::ListCompaniesTool, country: "Switzerland")
      assert_equal 0, swiss["count"]
      us = call(Mcp::Tools::ListCompaniesTool, country: "United States")
      assert_operator us["count"], :>=, 2
    end

    test "list_companies rejects an unknown review_state instead of returning everything" do
      response = Mcp::Tools::ListCompaniesTool.call(server_context: @context, review_state: "bogus")
      assert response.error?
      body = JSON.parse(response.to_h[:content].first[:text])
      assert_match(/Unknown review_state/, body["error"])
    end

    test "list_companies accepts needs_review as an alias for in_review" do
      companies(:one).update_column(:quality_status, "needs_review")
      companies(:two).update_column(:quality_status, "")
      result = call(Mcp::Tools::ListCompaniesTool, review_state: "needs_review")
      ids = result["companies"].map { |c| c["id"] }
      assert_includes ids, 1
      assert_not_includes ids, 2
    end

    test "list_companies rejects an unknown url_health_status" do
      response = Mcp::Tools::ListCompaniesTool.call(server_context: @context, url_health_status: "flaky")
      assert response.error?
    end

    test "list_companies filters by url_health_status untried" do
      companies(:one).update_columns(url_status: Company::URL_STATUS_OK, url_checked_at: Time.current)
      untried = call(Mcp::Tools::ListCompaniesTool, url_health_status: "untried")
      ids = untried["companies"].map { |c| c["id"] }
      assert_not_includes ids, 1
      assert_includes ids, 2
    end

    test "list_companies filters by url_reason and surfaces reason_code" do
      companies(:one).update_columns(url_status: Company::URL_STATUS_UNKNOWN, url_checked_at: Time.current, url_health: { "reason_code" => "dns_failure", "reason" => "SocketError" })
      companies(:two).update_columns(url_status: Company::URL_STATUS_UNKNOWN, url_checked_at: Time.current, url_health: { "reason_code" => "bot_blocked" })

      result = call(Mcp::Tools::ListCompaniesTool, url_reason: "dns_failure")
      ids = result["companies"].map { |c| c["id"] }
      assert_includes ids, 1
      assert_not_includes ids, 2
      row = result["companies"].find { |c| c["id"] == 1 }
      assert_equal "dns_failure", row["url_reason_code"]
    end

    test "get_stats url_health.by_reason classifies non-ok verdicts" do
      companies(:one).update_columns(url_status: Company::URL_STATUS_BROKEN, url_checked_at: Time.current, url_health: { "reason_code" => "http_404" })
      companies(:two).update_columns(url_status: Company::URL_STATUS_UNKNOWN, url_checked_at: Time.current, url_health: { "reason" => "server responded 403 (access-restricted)" })
      Rails.cache.clear
      result = call(Mcp::Tools::GetStatsTool, fresh: true)
      by_reason = result["companies"]["url_health"]["by_reason"]
      assert_operator by_reason["http_404"].to_i, :>=, 1
      # derived from free-text on the row that has no stored reason_code
      assert_operator by_reason["bot_blocked"].to_i, :>=, 1
    end

    test "get_stats url_health scopes by_reason_broken and by_reason_unknown by verdict" do
      companies(:one).update_columns(url_status: Company::URL_STATUS_BROKEN, url_checked_at: Time.current, url_health: { "reason_code" => "http_404" })
      companies(:two).update_columns(url_status: Company::URL_STATUS_UNKNOWN, url_checked_at: Time.current, url_health: { "reason_code" => "bot_blocked" })
      Rails.cache.clear
      url_health = call(Mcp::Tools::GetStatsTool, fresh: true)["companies"]["url_health"]

      # http_404 is a broken-only cause; bot_blocked is an unknown-only cause here.
      assert_operator url_health["by_reason_broken"]["http_404"].to_i, :>=, 1
      assert_nil url_health["by_reason_broken"]["bot_blocked"]
      assert_operator url_health["by_reason_unknown"]["bot_blocked"].to_i, :>=, 1
      assert_nil url_health["by_reason_unknown"]["http_404"]
    end

    test "get_backfill_run summarizes filled, no_source and pending outcomes for a run" do
      started = Time.current
      run = PipelineRun.create!(name: "Founded-date backfill batch", run_type: Mcp::Tools::BackfillFoundedDatesTool::RUN_TYPE, status: "running", started_at: started, records_processed: 3, details: { "company_ids" => [companies(:one).id, companies(:two).id, 999_999], "enqueued" => 3, "targeted" => true })
      companies(:one).update_columns(founded_date: "2015-01-01", founded_year_provenance: { "status" => "filled", "attempted_at" => (started + 1.second).utc.iso8601 })
      companies(:two).update_columns(founded_date: "", founded_year_provenance: { "status" => "no_source", "attempted_at" => (started + 1.second).utc.iso8601 })

      result = call(Mcp::Tools::GetBackfillRunTool, run_id: run.id)
      assert_equal "succeeded", result["status"]
      assert_equal 1, result["filled"]
      assert_equal 1, result["no_source"]
      assert_equal 1, result["missing"]
      assert_equal 0, result["pending"]
    end

    test "get_backfill_run marks companies not yet attempted as pending" do
      started = Time.current
      run = PipelineRun.create!(name: "Founded-date backfill batch", run_type: Mcp::Tools::BackfillFoundedDatesTool::RUN_TYPE, status: "running", started_at: started, records_processed: 1, details: { "company_ids" => [companies(:one).id], "enqueued" => 1, "targeted" => false })
      companies(:one).update_columns(founded_date: "", founded_year_provenance: nil)

      result = call(Mcp::Tools::GetBackfillRunTool, run_id: run.id)
      assert_equal "running", result["status"]
      assert_equal 1, result["pending"]
    end

    test "list_duplicate_candidates returns flagged pairs with match type" do
      make_company(name: "Avokati AI", url: "http://avokati.example")
      make_company(name: "Avokati AI", url: "http://avokati.example")

      result = call(Mcp::Tools::ListDuplicateCandidatesTool)
      pair = result["pairs"].find { |p| p["name_a"] == "Avokati AI" && p["name_b"] == "Avokati AI" }
      assert pair, result["pairs"].inspect
      assert_equal "name+domain", pair["match_type"]
      assert_operator pair["confidence"], :>, 0.9
    end

    test "list_duplicate_candidates filters by match_type" do
      make_company(name: "Solo Name Co", url: "http://solo-a.example")
      make_company(name: "Solo Name Co", url: "http://solo-b.example")

      name_only = call(Mcp::Tools::ListDuplicateCandidatesTool, match_type: "name")
      pair = name_only["pairs"].find { |p| p["name_a"] == "Solo Name Co" }
      assert pair
      assert_equal "name", pair["match_type"]

      domain_only = call(Mcp::Tools::ListDuplicateCandidatesTool, match_type: "domain")
      assert_nil domain_only["pairs"].find { |p| p["name_a"] == "Solo Name Co" }
    end

    test "duplicate detector excludes hidden rows so resolved pairs drop out of the queue" do
      a = make_company(name: "DupDetector Co", url: "http://dupdetector.example")
      b = make_company(name: "DupDetector Co", url: "http://dupdetector.example")
      pair = ->(result) { result["pairs"].find { |p| [p["company_id_a"], p["company_id_b"]].sort == [a.id, b.id].sort } }

      assert pair.call(call(Mcp::Tools::ListDuplicateCandidatesTool)), "pair should surface while both are visible"

      b.update!(visible: false)
      assert_nil pair.call(call(Mcp::Tools::ListDuplicateCandidatesTool)), "hiding the loser should drop the pair"
    end

    test "duplicate detector excludes rejected-quality rows" do
      a = make_company(name: "RejDetector Co", url: "http://rejdetector.example")
      b = make_company(name: "RejDetector Co", url: "http://rejdetector.example")
      b.update!(quality_status: "rejected")

      result = call(Mcp::Tools::ListDuplicateCandidatesTool)
      assert_nil result["pairs"].find { |p| [p["company_id_a"], p["company_id_b"]].sort == [a.id, b.id].sort }
    end

    test "merge_companies previews without deleting when unauthorized" do
      keeper = make_company(name: "Avvoka", url: "http://avvoka.example")
      dup = make_company(name: "Avvoka", url: "http://avvoka.example")
      keeper.update_columns(total_funding_amount_usd: nil)
      dup.update_columns(total_funding_amount_usd: 5_000_000)

      result = nil
      assert_no_difference "Company.count" do
        result = call(Mcp::Tools::MergeCompaniesTool, keep_id: keeper.id, merge_ids: [dup.id])
      end
      assert_equal "preview", result["result"]
      assert result["requires_confirmation"]
      assert_equal [dup.id], result["duplicate_ids"]
      assert_equal 5_000_000, result["filled_fields"][dup.id.to_s]["total_funding_amount_usd"].to_i
      assert Company.exists?(dup.id)
    end

    test "merge_companies folds blank fields and deletes the duplicate when authorized" do
      keeper = make_company(name: "Avvoka", url: "http://avvoka.example")
      dup = make_company(name: "Avvoka", url: "http://avvoka.example")
      keeper.update_columns(total_funding_amount_usd: nil, founders: nil)
      dup.update_columns(total_funding_amount_usd: 5_000_000, founders: "Jane Doe")

      result = nil
      assert_difference "Company.count", -1 do
        result = call(Mcp::Tools::MergeCompaniesTool, keep_id: keeper.id, merge_ids: [dup.id], human_approved: true)
      end
      assert_equal "merged", result["result"]
      assert_equal [dup.id], result["deleted_company_ids"]
      assert_not Company.exists?(dup.id)
      keeper.reload
      assert_equal 5_000_000, keeper.total_funding_amount_usd.to_i
      assert_equal "Jane Doe", keeper.founders
    end

    test "merge_companies refuses to delete an acquired duplicate" do
      keeper = make_company(name: "MergeAcq Co", url: "http://mergeacq.example")
      dup = make_company(name: "MergeAcq Co", url: "http://mergeacq.example")
      dup.update_columns(status: "acquired")

      response = Mcp::Tools::MergeCompaniesTool.call(server_context: @context, keep_id: keeper.id, merge_ids: [dup.id], human_approved: true)
      assert response.error?
      assert Company.exists?(dup.id)
    end

    test "merge_companies executes autonomously with sufficient confidence" do
      keeper = make_company(name: "ConfMerge Co", url: "http://confmerge.example")
      dup = make_company(name: "ConfMerge Co", url: "http://confmerge.example")

      with_env("MCP_CURATOR_MIN_CONFIDENCE" => "0.8") do
        assert_difference "Company.count", -1 do
          result = call(Mcp::Tools::MergeCompaniesTool, keep_id: keeper.id, merge_ids: [dup.id], confidence: 0.95)
          assert_equal "merged", result["result"]
        end
      end
    end

    test "check_url_health reports skipped ids that have no main_url" do
      companies(:one).update_columns(main_url: "http://example.com", url_checked_at: nil)
      companies(:two).update_columns(main_url: "")
      result = call(Mcp::Tools::CheckUrlHealthTool, company_ids: [companies(:one).id, companies(:two).id])
      assert_includes result["company_ids"], companies(:one).id
      assert_includes result["skipped_company_ids"], companies(:two).id
      assert_equal 1, result["skipped"]
    end

    private

    def make_company(name:, url:)
      company = Company.new(
        name: name,
        location: "Boston, MA",
        description: "A sufficiently long neutral description for testing purposes.",
        main_url: url,
        visible: true,
        category: categories(:one),
        business_model: business_models(:one),
        target_client: target_clients(:one)
      )
      company.skip_geocoding = true
      company.save!
      company
    end

    def with_env(vars)
      previous = {}
      vars.each { |key, value| previous[key] = ENV[key]; ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    def call(tool, **args)
      JSON.parse(tool.call(server_context: @context, **args).to_h[:content].first[:text])
    end

    def with_site_fetched(url)
      SiteEvidenceFetcherService.stub(:call, researched_agent_details(url: url)["site_evidence"]) { yield }
    end

    def pending_proposal
      CompanyProposal.create!(
        status: "pending",
        proposal_type: "atlas_candidate",
        source: "legaltechatlas_csv",
        source_identifier: "curator-tool-#{SecureRandom.hex(4)}",
        source_payload: { "name" => "Curator Test Co", "website" => "https://curator-test.example" },
        proposed_changes: { "name" => "Curator Test Co", "main_url" => "https://curator-test.example" },
        final_changes: {},
        duplicate_signals: {}
      )
    end

    # A second index row that agrees on the core name and on the brand label read out of
    # that same core, with the domains disagreeing: one evidence family, nothing
    # alone-eligible, so the pair grades advisory.
    def advisory_neighbour!(name:, url:)
      neighbour = companies(:two)
      neighbour.update!(name: name, main_url: url)
      neighbour.update_columns(canonical_domain: Company.canonical_domain_for(url), visible: true, quality_status: nil)
      neighbour
    end

    def ready_proposal
      CompanyProposal.create!(
        status: "ready_for_review",
        proposal_type: "atlas_candidate",
        source: "legaltechatlas_csv",
        source_identifier: "curator-ready-#{SecureRandom.hex(4)}",
        source_payload: { "name" => "Ready Co", "website" => "https://ready.example" },
        proposed_changes: { "name" => "Ready Co", "main_url" => "https://ready.example" },
        final_changes: {
          "name" => "Ready Co",
          "main_url" => "https://ready.example",
          "location" => "Boston, MA",
          "founded_date" => "2022",
          "description" => "Ready Co develops legal technology for contract review workflows used by law firms.",
          "category_id" => categories(:one).id,
          "business_model_id" => business_models(:one).id,
          "target_client_id" => target_clients(:one).id
        },
        duplicate_signals: {},
        enriched_at: Time.current,
        agent_details: researched_agent_details(url: "https://ready.example")
      )
    end
  end
end
