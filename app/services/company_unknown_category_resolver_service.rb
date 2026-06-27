class CompanyUnknownCategoryResolverService
  HIGH_CONFIDENCE = 0.85
  REVIEW_CONFIDENCE = 0.65

  def self.call(company:, dry_run: true, min_confidence: nil)
    new(company: company, dry_run: dry_run, min_confidence: min_confidence).call
  end

  def initialize(company:, dry_run: true, min_confidence: nil)
    @company = company
    @dry_run = dry_run
    @min_confidence = min_confidence || ENV.fetch("MIN_CONFIDENCE", HIGH_CONFIDENCE.to_s).to_f
  end

  def call
    return skip("not_unknown") unless company.category&.name == "Unknown"

    crosswalk = CategoryMigrationService.call(company: company, dry_run: dry_run)
    if crosswalk["action"].in?(%w[would_migrate migrated])
      return crosswalk.merge(
        "to_category" => crosswalk["to_category"],
        "confidence" => 0.9,
        "mode" => "crosswalk",
        "action" => dry_run ? "would_resolve" : "resolved"
      )
    end

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
    return skip("no_suggestion", category_name, confidence, suggestion["mode"]) if category_name.blank? || category_name == "Unknown"
    return skip("low_confidence", category_name, confidence, suggestion["mode"]) if confidence < min_confidence

    target_category = Category.find_by(name: category_name)
    return skip("missing_category", category_name, confidence, suggestion["mode"]) unless target_category

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

  attr_reader :company, :dry_run, :min_confidence

  def skip(reason, suggested_category = nil, confidence = nil, mode = nil)
    {
      "company_id" => company.id,
      "company_name" => company.name,
      "suggested_category" => suggested_category,
      "confidence" => confidence,
      "mode" => mode,
      "action" => "skipped_#{reason}"
    }
  end
end
