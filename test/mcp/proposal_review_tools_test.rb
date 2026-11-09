require "test_helper"

module Mcp
  class ProposalReviewToolsTest < ActiveSupport::TestCase
    setup do
      AdminUser.find_or_create_by!(email: Mcp::CuratorActor.email) do |user|
        user.password = "password123"
        user.password_confirmation = "password123"
      end
      @context = { actor: "test" }
      @proposal = CompanyProposal.create!(
        status: "ready_for_review", proposal_type: "discovery_candidate", source: "llm_discovery",
        source_identifier: SecureRandom.uuid, source_payload: {}, duplicate_signals: {},
        proposed_changes: { "name" => "Zephyr Review" }, final_changes: { "name" => "Zephyr Review" }
      )
    end

    def call(tool, **args)
      JSON.parse(tool.call(server_context: @context, **args).to_h[:content].first[:text])
    end

    test "record_proposal_review records a no-change review that get_proposal and the queue report" do
      result = call(Tools::RecordProposalReviewTool, id: @proposal.id, outcome: "no_change", note: "Site checked.")

      assert_equal "no_change", result["review"]["outcome"]
      assert_match(/\AReviewed — no change \| /, result["label"])
      assert_equal "ready_for_review", @proposal.reload.status

      fetched = call(Tools::GetProposalTool, id: @proposal.id)
      assert_equal "no_change", fetched["review_log"].last["outcome"]

      queue = call(Tools::ListReviewQueueTool, query: "Zephyr Review")
      assert_equal "no_change", queue["proposals"].first["last_review"]["outcome"]

      filtered = call(Tools::ListReviewQueueTool, query: "Zephyr Review", exclude_reviewed: true)
      assert_equal 0, filtered["total"]
    end

    test "record_proposal_review refuses a closed proposal" do
      @proposal.update!(status: "rejected", rejected_at: Time.current)

      response = Tools::RecordProposalReviewTool.call(server_context: @context, id: @proposal.id, outcome: "no_change")

      assert response.error?
      assert_empty @proposal.reload.review_log
    end

    test "record_proposal_review is exposed to the curator" do
      assert_includes Tools.all, Tools::RecordProposalReviewTool
    end

    test "search_companies says how each name relates to the query" do
      assert_equal "exact", Tools::SearchCompaniesTool.name_match("ligi.ai", "ligi.ai")
      assert_equal "same_core", Tools::SearchCompaniesTool.name_match("Ligi", "ligi.ai")
      assert_equal "partial", Tools::SearchCompaniesTool.name_match("ligi", "Eligible Legal")
      assert_equal "none", Tools::SearchCompaniesTool.name_match("ligi", "Acme")
    end
  end
end
