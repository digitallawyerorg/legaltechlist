class CompanyUnknownTargetClientResolverService
  CATEGORY_DEFAULTS = {
    "Practice Management" => "Law Firms",
    "Legal Operations / ELM" => "Corporate Legal",
    "Marketplace and ALSPs" => "Legal Service Providers",
    "Access to Justice & Public Sector" => "Consumers",
    "Knowledge & Research" => "Law Firms",
    "eDiscovery & Investigations" => "Law Firms"
  }.freeze

  def self.call(company:, dry_run: true, min_confidence: nil)
    new(company: company, dry_run: dry_run, min_confidence: min_confidence).call
  end

  def initialize(company:, dry_run: true, min_confidence: nil)
    @company = company
    @dry_run = dry_run
    @min_confidence = min_confidence || ENV.fetch("MIN_CONFIDENCE", "0.55").to_f
  end

  def call
    return skip("not_unknown") unless company.target_client&.name == "Unknown"

    suggestion = CompanyProposalTaxonomySuggestionService.call(
      source_payload: {
        "name" => company.name,
        "website" => company.main_url,
        "source_description" => company.description,
        "industries" => [company.category&.name].compact
      },
      final_changes: {}
    )

    client_name = suggestion.dig("target_client", "name")
    confidence = suggestion.dig("target_client", "confidence").to_f
    target_client = TaxonomyNormalizationService.find_target_client(client_name)

    if target_client.blank? || confidence < min_confidence
      fallback_name = CATEGORY_DEFAULTS[company.category&.name]
      target_client = TargetClient.find_by(name: fallback_name) if fallback_name.present?
      if target_client
        client_name = fallback_name
        confidence = 0.55
      else
        return skip("no_match", client_name, confidence, suggestion["mode"])
      end
    end

    unless dry_run
      company.target_client_id = target_client.id
      company.target_client_ids = [target_client.id]
      company.save!(validate: false)
    end

    {
      "company_id" => company.id,
      "company_name" => company.name,
      "to_target_client" => client_name,
      "confidence" => confidence,
      "mode" => suggestion["mode"],
      "action" => dry_run ? "would_resolve" : "resolved"
    }
  end

  private

  attr_reader :company, :dry_run, :min_confidence

  def skip(reason, suggested = nil, confidence = nil, mode = nil)
    {
      "company_id" => company.id,
      "company_name" => company.name,
      "suggested_target_client" => suggested,
      "confidence" => confidence,
      "mode" => mode,
      "action" => "skipped_#{reason}"
    }
  end
end
