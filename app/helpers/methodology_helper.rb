module MethodologyHelper
  REVENUE_MODELS = [
    { name: "Subscription", definition: "Monthly or annual recurring revenue, seat-based pricing, or tiered plans." },
    { name: "Usage-Based", definition: "Consumption-based billing for API calls, storage, compute, or per-unit usage." },
    { name: "Transaction Fee", definition: "Commissions, take rates, or fees on payments and marketplace transactions." },
    { name: "Services", definition: "Hourly, project, retainer, or managed-service delivery by people." },
    { name: "Licensing", definition: "Software or IP licensing fees and royalties." },
    { name: "Advertising", definition: "Advertising, sponsorships, and ad-supported revenue." },
    { name: "Commerce", definition: "One-time product sales, physical or digital." },
    { name: "Success Fee", definition: "Performance-based fees, including recruiting, M&A, contingency, or outcome pricing." },
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
        { name: "target_clients", type: "List", description: "Buyers or audiences served (one or more)." },
        { name: "tags", type: "List", description: "Technology and theme keywords." }
      ]
    },
    {
      label: "Location & geography",
      fields: [
        { name: "country", type: "Text", description: "Headquarters country (canonical name for filters and statistics)." },
        { name: "city", type: "Text", description: "Headquarters city when known." },
        { name: "location", type: "Text", description: "Legacy display string (city, country). Kept in sync with country and city." },
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
      label: "Company references",
      fields: [
        { name: "facebook_url", type: "URL", description: "Facebook page." },
        { name: "linkedin_url", type: "URL", description: "LinkedIn company page." },
        { name: "twitter_url", type: "URL", description: "Twitter / X profile." }
      ]
    },
    {
      label: "External references",
      fields: [
        { name: "crunchbase_url", type: "URL", description: "Crunchbase profile." },
        { name: "legalio_url", type: "URL", description: "Legal.io profile." }
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
    { name: "IP Management", definition: "Intellectual property portfolios covering patents, trademarks, and copyrights." },
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

  OVERVIEW_GUIDANCE = "The CodeX TechIndex currently tracks %<count>s legal-technology companies across %<category_count>s primary functional categories. Companies are added on an ongoing basis and requests for corrections are welcomed.".freeze

  ELIGIBILITY_GUIDANCE = "A legal technology company is a market-facing vendor whose principal business is software, data, or technology-enabled services for legal work. Each index entry is one company or brand, not an individual product. We exclude law firms and consultancies engaged primarily in legal service delivery, standalone products for companies already indexed, and vendors not substantially focused on legal use cases.".freeze

  CATEGORY_GUIDANCE = "Each company profile has one primary category that reflects its core function. Revenue model, target client, and secondary category draw from the fixed lists below. Tags are separate technology and theme keywords. All other attributes are named fields on the record.".freeze

  REVENUE_MODEL_GUIDANCE = "How the company earns or sustains operations, not its product category. Select all that apply; venture funding is tracked separately.".freeze

  TAG_GUIDANCE = "Technology and theme keywords that cross-cut primary categories, such as artificial intelligence, eDiscovery, and SaaS. A company may have several. Tags power the technology themes and AI trends charts; similar terms are normalized to a shared vocabulary rather than a fixed pick list.".freeze

  STATISTICS_GUIDANCE = "Statistics charts use the company profiles described above. They cover publicly listed companies when we have the information needed for that chart. Each company in the index is counted separately. Related entities under the same corporate parent are not combined. Acquired companies remain in historical growth charts. Funding charts include only companies with reported funding. Map and geography charts include only companies with a known headquarters location.".freeze

  CITATIONS_GUIDANCE = "When referencing TechIndex data, include the page URL and access date. Copy an example below and adapt the title or URL as needed.".freeze

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
    format(OVERVIEW_GUIDANCE, count: count, category_count: PRIMARY_CATEGORIES.size)
  end

  def methodology_overview_html(count)
    safe_join([
      methodology_overview_guidance(count),
      " To request addition of a company, ",
      link_to("click here", new_company_path, class: "methodology-link"),
      "."
    ])
  end

  def methodology_revenue_model_guidance
    REVENUE_MODEL_GUIDANCE
  end

  def methodology_tags_guidance
    TAG_GUIDANCE
  end

  def methodology_statistics_guidance
    STATISTICS_GUIDANCE
  end

  def methodology_category_guidance
    CATEGORY_GUIDANCE
  end

  def methodology_eligibility_guidance
    ELIGIBILITY_GUIDANCE
  end

  def methodology_citations_guidance
    CITATIONS_GUIDANCE
  end

  def methodology_citation_accessed_on
    Date.current.strftime("%B %-d, %Y")
  end

  def methodology_citation_url_options
    uri = URI.parse(site_url)
    { host: uri.host, protocol: uri.scheme }
  end

  def methodology_citation_entries
    accessed_on = methodology_citation_accessed_on
    url_options = methodology_citation_url_options
    example_company = Company.publicly_visible.order(:name).first

    record_citation = if example_company
                        "Stanford Center for Legal Informatics (CodeX), CodeX TechIndex, #{example_company.name}, #{company_url(example_company, **url_options)} (last visited #{accessed_on})."
                      else
                        "Stanford Center for Legal Informatics (CodeX), CodeX TechIndex, [Company Name], #{site_url}/companies/[slug] (last visited #{accessed_on})."
                      end

    [
      {
        icon: "fa-solid fa-globe",
        icon_color: "#2563eb",
        citation: "Stanford Center for Legal Informatics (CodeX). CodeX TechIndex. #{root_url(**url_options)} (last visited #{accessed_on})."
      },
      {
        icon: "fa-solid fa-building",
        icon_color: "#8c1515",
        citation: record_citation
      },
      {
        icon: "fa-solid fa-chart-line",
        icon_color: "#047857",
        citation: "Stanford Center for Legal Informatics (CodeX), CodeX TechIndex, Category Evolution, #{statistics_category_evolution_5_years_url(**url_options)} (last visited #{accessed_on})."
      }
    ]
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
