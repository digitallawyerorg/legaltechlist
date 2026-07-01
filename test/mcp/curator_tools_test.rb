require "test_helper"

module Mcp
  class CuratorToolsTest < ActiveSupport::TestCase
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
      proposal.update!(agent_details: { "taxonomy_suggestion" => { "accepted" => false } })
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

    test "get_stats returns directory and backlog counts" do
      result = call(Mcp::Tools::GetStatsTool)
      assert result["companies"].key?("total")
      assert result["proposals"].key?("by_status")
      assert result["curator"].key?("min_confidence")
    end

    test "suggest_improvement records an audit run" do
      assert_difference -> { PipelineRun.where(run_type: "curator_mcp").count }, 1 do
        result = call(Mcp::Tools::SuggestImprovementTool, suggestion: "Add a bulk re-tagging tool.", area: "tooling")
        assert result["recorded"]
      end
    end

    private

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
        duplicate_signals: {}
      )
    end
  end
end
