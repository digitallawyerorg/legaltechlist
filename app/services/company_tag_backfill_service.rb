class CompanyTagBackfillService
  DESCRIPTION_PATTERNS = {
    "artificial intelligence" => /\b(ai|artificial intelligence|machine learning|generative ai|llm)\b/i,
    "saas" => /\b(saas|software as a service|cloud platform|subscription software)\b/i,
    "compliance" => /\b(compliance|regulatory|gdpr|privacy)\b/i,
    "automation" => /\b(automation|automated|workflow)\b/i,
    "document management" => /\b(document management|document automation|document assembly)\b/i,
    "contract management" => /\b(contract management|contract lifecycle|\bclm\b)\b/i,
    "practice management" => /\b(practice management|legal billing|time tracking)\b/i,
    "e-discovery" => /\b(ediscovery|e-discovery|electronic discovery)\b/i,
    "legal research" => /\b(legal research|case law|legal database)\b/i,
    "blockchain" => /\b(blockchain|smart contract)\b/i,
    "marketplace" => /\b(marketplace|platform connecting)\b/i
  }.freeze

  def self.call(company:, dry_run: true, max_tags: 5)
    new(company: company, dry_run: dry_run, max_tags: max_tags).call
  end

  def initialize(company:, dry_run: true, max_tags: 5)
    @company = company
    @dry_run = dry_run
    @max_tags = max_tags
  end

  def call
    return skip("already_tagged") if company.tags.any?

    text = [company.name, company.description, company.category&.name, company.target_client&.name].compact.join(" ")
    names = DESCRIPTION_PATTERNS.filter_map { |tag, pattern| tag if text.match?(pattern) }.first(max_tags)
    return skip("no_signals") if names.empty?

    unless dry_run
      company.tags = names.filter_map { |name| TagNormalizationService.find_or_create_canonical(name) }
    end

    {
      "company_id" => company.id,
      "company_name" => company.name,
      "suggested_tags" => names,
      "action" => dry_run ? "would_tag" : "tagged"
    }
  end

  private

  attr_reader :company, :dry_run, :max_tags

  def skip(reason)
    {
      "company_id" => company.id,
      "company_name" => company.name,
      "action" => "skipped_#{reason}"
    }
  end
end
