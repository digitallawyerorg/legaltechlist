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
        GetTaxonomyTool,
        # Discovery
        DiscoverCompaniesTool,
        # Proposal curation (tiered)
        EnrichProposalTool,
        AssessProposalTool,
        UpdateProposalTool,
        CuratePendingTool,
        ApproveProposalTool,
        RejectProposalTool,
        # Maintenance of existing entries
        RunCompanyReviewTool,
        ProposeCompanyUpdateTool,
        ApplySafeFieldsTool,
        MarkReviewTool,
        SuggestTaxonomyTool,
        # Meta
        SuggestImprovementTool
      ]
    end
  end
end
