module Mcp
  module Tools
    module_function

    # Ordered list of curator tool classes exposed to Claude Tag.
    def all
      [
        # Read / context
        SearchCompaniesTool,
        GetCompanyTool,
        ListReviewQueueTool,
        GetProposalTool,
        DuplicateCheckTool,
        # Discovery
        DiscoverCompaniesTool,
        # Proposal curation (tiered)
        EnrichProposalTool,
        AssessProposalTool,
        CuratePendingTool,
        ApproveProposalTool,
        RejectProposalTool,
        # Maintenance of existing entries
        RunCompanyReviewTool,
        ApplySafeFieldsTool,
        MarkReviewTool,
        SuggestTaxonomyTool
      ]
    end
  end
end
