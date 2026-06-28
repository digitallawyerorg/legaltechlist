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
        { name: "target_clients", type: "List", description: "Buyers or audiences served (one or more canonical values)." },
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
        { name: "successor_company", type: "Reference", description: "Link to the successor record after acquisition or rebrand." },
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
    { name: "Document Management and Automation", definition: "Systems for creating, organizing, storing, and automating legal documents." },
    { name: "Compliance & Risk", definition: "Solutions for regulatory compliance, data privacy, cybersecurity, anti-corruption, and ESG risk management." },
    { name: "Practice Management", definition: "Client intake, calendaring, billing, and case tracking for law firm practice operations (excluding enterprise legal management)." },
    { name: "Marketplace and ALSPs", definition: "Alternative legal service providers, talent platforms, and flexible legal resourcing marketplaces." },
    { name: "Litigation & Dispute Resolution", definition: "Litigation management, case workflow, and alternative dispute resolution (excluding dedicated eDiscovery platforms)." },
    { name: "Knowledge & Research", definition: "Legal databases, institutional knowledge management, and practical guidance resources." },
    { name: "Contract Management", definition: "Drafting, reviewing, negotiating, and managing contracts throughout their lifecycle." },
    { name: "IP Management", definition: "Intellectual property portfolios — patents, trademarks, and copyrights." },
    { name: "Analytics & Insights", definition: "Predictive models, data visualization, and benchmarking for legal decision-making." },
    { name: "eDiscovery & Investigations", definition: "Review, processing, and analysis of electronically stored information for litigation and investigations." },
    { name: "Legal Operations / ELM", definition: "Matter management, e-billing, spend management, and legal operations for corporate legal departments." },
    { name: "Access to Justice & Public Sector", definition: "Self-help, legal aid, court, and government-facing tools for access to justice and public-sector legal services." }
  ].freeze

  PRIMARY_CATEGORY_NAMES = PRIMARY_CATEGORIES.map { |row| row[:name] }.freeze

  TARGET_CLIENTS = [
    { name: "Law Firms", definition: "Products and services for law firms and legal practices of all sizes." },
    { name: "Corporate Legal", definition: "Solutions for in-house legal departments and corporate counsel." },
    { name: "Government", definition: "Services for government legal departments, courts, and agencies." },
    { name: "Consumers", definition: "Direct-to-consumer legal tools, self-service applications, and public-facing legal help." },
    { name: "Legal Education", definition: "Tools for law schools, continuing education, and legal training." },
    { name: "Legal Service Providers", definition: "Solutions for alternative legal service providers and legal-tech-enabled service firms." }
  ].freeze

  OVERVIEW_GUIDANCE = "The TechIndex tracks legal-technology companies — market-facing vendors, not individual products. Each profile is one company. The index lists %<count>s companies across twelve primary functional categories (taxonomy v2, June 2026). Acquired companies stay in the index with status, exit date, and successor link when applicable.".freeze

  CATEGORY_GUIDANCE = "Twelve mutually exclusive primary categories. eDiscovery, legal operations / ELM, and access-to-justice segments were split from litigation, practice management, and cross-cutting A2J vendors in the 2026 taxonomy migration.".freeze

  ENTITY_RELATIONSHIPS = [
    { term: "Duplicate", definition: "Same identity entered twice — merge or hide the extra record." },
    { term: "Acquisition", definition: "Distinct companies — keep both records; mark acquiree as acquired with exit date and link to successor." },
    { term: "Rebrand", definition: "Same company, new name — keep old record; link to successor." },
    { term: "Related", definition: "Distinct brands under one corporate family — keep both; link when useful for discovery." }
  ].freeze

  REVENUE_MODEL_GUIDANCE = "How the company earns or sustains operations — not its product category. Select all that apply; venture funding is tracked separately.".freeze

  SECONDARY_CATEGORY_GUIDANCE = "Optional second functional segment from the same twelve-category list (e.g. Legal.io: Marketplace primary, Knowledge & Research secondary). Excluded from primary trend counts.".freeze

  STATISTICS_CONVENTIONS = [
    "Counts are index entries (companies), not deduplicated corporate parents. Acquired companies remain in historical cohort charts.",
    "Most charts include companies founded 2000 or later with an assigned primary category.",
    "Category evolution uses the v2 twelve-category spine; historical series were back-mapped via published crosswalk.",
    "Secondary category and multi-value revenue models do not change primary category counts; revenue charts count once per selected model.",
    "Target client statistics use canonical multi-value assignments where available.",
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

  def methodology_category_guidance
    CATEGORY_GUIDANCE
  end

  def methodology_category_rows
    counts = Category.where(name: PRIMARY_CATEGORY_NAMES)
                     .left_joins(:companies)
                     .where(companies: { visible: true })
                     .group("categories.id", "categories.name")
                     .count

    PRIMARY_CATEGORIES.map do |row|
      category = Category.find_by(name: row[:name])
      row.merge(count: counts[[category&.id, row[:name]]].to_i)
    end.sort_by { |row| -row[:count] }
  end
end
