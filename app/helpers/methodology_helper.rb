module MethodologyHelper
  REVENUE_MODELS = [
    { name: "Subscription", definition: "Monthly or annual recurring revenue, seat-based pricing, or tiered plans." },
    { name: "Usage-Based", definition: "Consumption-based billing — API calls, storage, compute, or per-unit usage." },
    { name: "Transaction Fee", definition: "Commissions, take rates, or fees on payments and marketplace transactions." },
    { name: "Services", definition: "Hourly, project, retainer, or managed-service delivery by people." },
    { name: "Licensing", definition: "Software or IP licensing fees and royalties." },
    { name: "Advertising", definition: "Advertising, sponsorships, and ad-supported revenue." },
    { name: "Commerce", definition: "One-time product sales, physical or digital." },
    { name: "Success Fee", definition: "Performance-based fees — recruiting, M&A, contingency, or outcome pricing." },
    { name: "Grants & Subsidies", definition: "Grants, donations, or public subsidies (legal aid, A2J, nonprofits)." },
    { name: "Other", definition: "Does not fit the categories above." }
  ].freeze

  REVENUE_MODEL_NAMES = REVENUE_MODELS.map { |row| row[:name] }.freeze

  COMPANY_FIELD_GROUPS = [
    {
      label: "Identity & profile",
      fields: [
        { name: "name", type: "Text", description: "Market-facing company or brand name." },
        { name: "description", type: "Text", description: "Neutral summary of what the company does." },
        { name: "main_url", type: "URL", description: "Primary company website." },
        { name: "logo_url", type: "URL", description: "Logo image URL when available." }
      ]
    },
    {
      label: "Classification",
      fields: [
        { name: "category", type: "Reference", description: "Primary functional segment (one per company). Drives category statistics." },
        { name: "secondary_category", type: "Reference", description: "Optional second segment from the same category list. Excluded from primary trend counts." },
        { name: "revenue_models", type: "List", description: "How the company earns or sustains operations (one or more)." },
        { name: "target_client", type: "Reference", description: "Primary buyer or audience." },
        { name: "tags", type: "List", description: "Technology and theme keywords." }
      ]
    },
    {
      label: "Location & geography",
      fields: [
        { name: "location", type: "Text", description: "Headquarters (city, region, and/or country)." },
        { name: "headquarters_region", type: "Text", description: "Regional label when reported separately." },
        { name: "latitude / longitude", type: "Number", description: "Geocoded coordinates when available." }
      ]
    },
    {
      label: "Company lifecycle",
      fields: [
        { name: "founded_date", type: "Year (YYYY)", description: "Year founded." },
        { name: "status", type: "Text", description: "Active, inactive, acquired, merged, or rebranded. Acquired entries remain in the index." },
        { name: "employee_count", type: "Text", description: "Headcount or range when reported." },
        { name: "founders", type: "Text", description: "Named founders when reported." }
      ]
    },
    {
      label: "Funding & ownership",
      fields: [
        { name: "total_funding_amount_usd", type: "Currency (USD)", description: "Disclosed venture and growth equity funding (not grants)." },
        { name: "funding_status", type: "Text", description: "Latest funding stage (e.g. Seed, Series B)." },
        { name: "number_of_funding_rounds", type: "Integer", description: "Reported funding rounds." },
        { name: "exit_date", type: "Date", description: "Acquisition, merger, rebrand, or shutdown date." }
      ]
    },
    {
      label: "External links",
      fields: [
        { name: "crunchbase_url", type: "URL", description: "Crunchbase profile." },
        { name: "linkedin_url", type: "URL", description: "LinkedIn company page." },
        { name: "twitter_url", type: "URL", description: "Twitter / X profile." },
        { name: "facebook_url", type: "URL", description: "Facebook page." },
        { name: "angellist_url", type: "URL", description: "AngelList / Wellfound profile." },
        { name: "legalio_url", type: "URL", description: "Legal.io listing when applicable." }
      ]
    },
    {
      label: "Provenance",
      fields: [
        { name: "source", type: "Text", description: "How the entry entered the index." },
        { name: "source_url", type: "URL", description: "Supporting reference URL." }
      ]
    },
    {
      label: "CodeX program",
      fields: [
        { name: "codex_presenter", type: "Boolean", description: "Presented at a CodeX program or event." },
        { name: "codex_presentation_date", type: "Date", description: "CodeX presentation date." }
      ]
    }
  ].freeze

  PRIMARY_CATEGORIES = [
    { name: "Analytics & Insights", definition: "Quantitative and qualitative analysis tools supporting legal decision-making through predictive models, data visualization, and benchmarking." },
    { name: "Compliance & Risk", definition: "Solutions for regulatory compliance, data privacy, cybersecurity, anti-corruption, and ESG risk management." },
    { name: "Contract Management", definition: "Platforms for drafting, reviewing, negotiating, and managing contracts throughout their complete lifecycle." },
    { name: "Document Management and Automation", definition: "Systems for creating, organizing, storing, and automating legal documents." },
    { name: "IP Management", definition: "Tools for managing intellectual property portfolios, including patents, trademarks, and copyrights." },
    { name: "Knowledge & Research", definition: "Access to legal databases, institutional knowledge management, and practical guidance resources." },
    { name: "Litigation & Dispute Resolution", definition: "Technologies for litigation management, eDiscovery, and alternative dispute resolution." },
    { name: "Marketplace and ALSPs", definition: "Resources for accessing alternative legal service providers, legal talent platforms, and marketplaces for flexible resourcing and project-based legal solutions." },
    { name: "Practice Management", definition: "Platforms focused on the operational aspects of running a legal practice, including client management, calendaring, billing, and case tracking." }
  ].freeze

  PROPOSED_PRIMARY_CATEGORIES = [
    { name: "Document Management and Automation", status: "Unchanged", definition: "Systems for creating, organizing, storing, and automating legal documents." },
    { name: "Compliance & Risk", status: "Unchanged", definition: "Solutions for regulatory compliance, data privacy, cybersecurity, anti-corruption, and ESG risk management." },
    { name: "Practice Management", status: "Narrowed", definition: "Client intake, calendaring, billing, and case tracking for law firm practice operations (excluding enterprise legal management)." },
    { name: "Marketplace and ALSPs", status: "Unchanged", definition: "Alternative legal service providers, talent platforms, and flexible legal resourcing marketplaces." },
    { name: "Litigation & Dispute Resolution", status: "Narrowed", definition: "Litigation management, case workflow, and alternative dispute resolution (excluding dedicated eDiscovery platforms)." },
    { name: "Knowledge & Research", status: "Unchanged", definition: "Legal databases, institutional knowledge management, and practical guidance resources." },
    { name: "Contract Management", status: "Unchanged", definition: "Drafting, reviewing, negotiating, and managing contracts throughout their lifecycle." },
    { name: "IP Management", status: "Unchanged", definition: "Intellectual property portfolios — patents, trademarks, and copyrights." },
    { name: "Analytics & Insights", status: "Unchanged", definition: "Predictive models, data visualization, and benchmarking for legal decision-making." },
    { name: "eDiscovery & Investigations", status: "New", definition: "Review, processing, and analysis of electronically stored information for litigation and investigations." },
    { name: "Legal Operations / ELM", status: "New", definition: "Matter management, e-billing, spend management, and legal operations for corporate legal departments." },
    { name: "Access to Justice & Public Sector", status: "New", definition: "Self-help, legal aid, court, and government-facing tools for access to justice and public-sector legal services." }
  ].freeze

  PROPOSED_CATEGORY_SPLITS = {
    "Litigation & Dispute Resolution" => "eDiscovery & Investigations",
    "Practice Management" => "Legal Operations / ELM"
  }.freeze

  TARGET_CLIENTS = [
    { name: "Law Firms", definition: "Products and services for law firms and legal practices of all sizes." },
    { name: "Corporate Legal", definition: "Solutions for in-house legal departments and corporate counsel." },
    { name: "Government", definition: "Services for government legal departments, courts, and agencies." },
    { name: "Consumers", definition: "Direct-to-consumer legal tools, self-service applications, and public-facing legal help." },
    { name: "Legal Education", definition: "Tools for law schools, continuing education, and legal training." },
    { name: "Legal Service Providers", definition: "Solutions for alternative legal service providers and legal-tech-enabled service firms." }
  ].freeze

  OVERVIEW_GUIDANCE = "The TechIndex tracks legal-technology companies — market-facing vendors, not individual products. Each profile is one company. Acquired companies stay in the index (status and exit date updated; successor link planned). The index lists %<count>s companies today on nine primary categories; twelve are planned after targeted splits (see below).".freeze

  PROPOSED_CATEGORY_GUIDANCE = "Planned primary categories after data hygiene and a published crosswalk migration. Live assignments still use the nine categories above until migration ships.".freeze

  ENTITY_RELATIONSHIPS = [
    { term: "Duplicate", definition: "Same identity entered twice — merge or hide the extra record." },
    { term: "Related", definition: "Distinct brands under one corporate family, or acquirer and acquiree — keep both; link them." },
    { term: "Rebrand", definition: "Same company, new name — mark old record rebranded; link to successor." }
  ].freeze

  REVENUE_MODEL_GUIDANCE = "How the company earns or sustains operations — not its product category. Select all that apply; venture funding is tracked separately.".freeze

  SECONDARY_CATEGORY_GUIDANCE = "Optional second functional segment from the same twelve-category list (e.g. Legal.io: Marketplace primary, Knowledge & Research secondary). Excluded from primary trend counts.".freeze

  STATISTICS_CONVENTIONS = [
    "Counts are index entries (companies), not deduplicated corporate parents. Acquired companies remain in historical cohort charts.",
    "Most charts include companies founded 2000 or later with a assigned primary category.",
    "Category evolution shows cumulative companies founded through each period end.",
    "Secondary category and multi-value revenue models do not change primary category counts; revenue charts count once per selected model.",
    "Funding charts include only companies with disclosed funding greater than zero.",
    "Geographic charts require a parseable headquarters location.",
    "All primary categories and statistics segments are shown regardless of company count.",
    "Rare tags may be omitted from top-tag summaries only."
  ].freeze

  def methodology_company_field_groups
    COMPANY_FIELD_GROUPS
  end

  def methodology_primary_categories
    PRIMARY_CATEGORIES
  end

  def methodology_revenue_models
    REVENUE_MODELS
  end

  def methodology_target_clients
    TARGET_CLIENTS
  end

  def methodology_overview_guidance(count)
    format(OVERVIEW_GUIDANCE, count: count)
  end

  def methodology_entity_relationships
    ENTITY_RELATIONSHIPS
  end

  def methodology_revenue_model_guidance
    REVENUE_MODEL_GUIDANCE
  end

  def methodology_secondary_category_guidance
    SECONDARY_CATEGORY_GUIDANCE
  end

  def methodology_statistics_conventions
    STATISTICS_CONVENTIONS
  end

  def methodology_proposed_category_guidance
    PROPOSED_CATEGORY_GUIDANCE
  end

  def methodology_category_rows
    counts = Category.where.not(name: "Unknown")
                     .left_joins(:companies)
                     .where(companies: { visible: true })
                     .group("categories.id", "categories.name")
                     .count

    PRIMARY_CATEGORIES.map do |row|
      category = Category.find_by(name: row[:name])
      row.merge(count: counts[[category&.id, row[:name]]].to_i)
    end.sort_by { |row| -row[:count] }
  end

  def methodology_proposed_category_rows
    current_by_name = methodology_category_rows.index_by { |row| row[:name] }
    split_estimates = {
      "eDiscovery & Investigations" => estimate_ediscovery_count,
      "Legal Operations / ELM" => estimate_elm_count,
      "Access to Justice & Public Sector" => estimate_a2j_count
    }

    PROPOSED_PRIMARY_CATEGORIES.map do |row|
      count = case row[:status]
              when "Unchanged" then current_by_name.fetch(row[:name], { count: 0 })[:count]
              when "Narrowed"
                source_count = current_by_name.fetch(row[:name], { count: 0 })[:count]
                split_name = PROPOSED_CATEGORY_SPLITS[row[:name]]
                [source_count - split_estimates.fetch(split_name, 0), 0].max
              when "New" then split_estimates.fetch(row[:name], 0)
              else 0
              end

      row.merge(count: count, count_note: row[:status] == "Unchanged" ? nil : "est.")
    end.sort_by { |row| -row[:count] }
  end

  def estimate_ediscovery_count
    Company.publicly_visible
           .joins(:tags)
           .where("LOWER(tags.name) IN (?)", %w[ediscovery e-discovery e discovery])
           .distinct
           .count
  end

  def estimate_elm_count
    Company.publicly_visible
           .where("description ~* ?", '\y(legal operations|e-?billing|matter management|elm|enterprise legal management)\y')
           .count
  end

  def estimate_a2j_count
    Company.publicly_visible
           .joins(:tags)
           .where("LOWER(tags.name) ~ ?", "legal.?aid|access.?(to.?).?justice|pro.?bono")
           .distinct
           .count
  end
end
