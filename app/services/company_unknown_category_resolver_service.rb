class CompanyUnknownCategoryResolverService
  HIGH_CONFIDENCE = 0.85

  def self.call(company:, dry_run: true)
    new(company: company, dry_run: dry_run).call
  end

  def initialize(company:, dry_run: true)
    @company = company
    @dry_run = dry_run
  end

  def call
    return skip("not_unknown") unless company.category&.name == "Unknown"

    suggestion = CompanyProposalTaxonomySuggestionService.call(
      source_payload: {
        "name" => company.name,
        "website" => company.main_url,
        "source_description" => company.description,
        "industries" => [company.target_client&.name].compact
      },
      final_changes: {}
    )

    category_name = suggestion.dig("category", "name")
    confidence = suggestion.dig("category", "confidence").to_f
    return skip("no_suggestion") if category_name.blank? || category_name == "Unknown"
    return skip("low_confidence") if confidence < HIGH_CONFIDENCE

    target_category = Category.find_by(name: category_name)
    return skip("missing_category") unless target_category

    company.update!(category: target_category) unless dry_run

    {
      "company_id" => company.id,
      "company_name" => company.name,
      "to_category" => category_name,
      "confidence" => confidence,
      "mode" => suggestion["mode"],
      "action" => dry_run ? "would_resolve" : "resolved"
    }
  end

  private

  attr_reader :company, :dry_run

  def skip(reason)
    {
      "company_id" => company.id,
      "company_name" => company.name,
      "action" => "skipped_#{reason}"
    }
  end
end
