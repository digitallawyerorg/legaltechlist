class TaxonomyNormalizationService
  TARGET_CLIENT_ALIASES = {
    "individual consumers" => "Consumers",
    "individual consumer" => "Consumers",
    "individuals" => "Consumers",
    "individual" => "Consumers",
    "consumer" => "Consumers",
    "consumers" => "Consumers",
    "companies" => "Corporate Legal",
    "company" => "Corporate Legal",
    "enterprise" => "Corporate Legal",
    "enterprises" => "Corporate Legal",
    "in-house" => "Corporate Legal",
    "in house" => "Corporate Legal",
    "corporate" => "Corporate Legal",
    "corporate legal" => "Corporate Legal",
    "legal service provider" => "Legal Service Providers",
    "legal service providers" => "Legal Service Providers",
    "service providers" => "Legal Service Providers",
    "service provider" => "Legal Service Providers",
    "law firm" => "Law Firms",
    "law firms" => "Law Firms",
    "government" => "Government",
    "legal education" => "Legal Education",
    "courts" => "Government"
  }.freeze

  LEGACY_REVENUE_MODEL_MAP = {
    "SaaS" => ["Subscription"],
    "Publishing" => ["Licensing"],
    "Content Provider" => ["Licensing"],
    "Data & Analytics" => ["Subscription"],
    "Data" => ["Subscription"],
    "Managed Service" => ["Services"],
    "Legal Tech" => ["Subscription"],
    "Legal Service Using Tech" => ["Services", "Subscription"],
    "Legal Service" => ["Services"],
    "Marketplace" => ["Transaction Fee", "Subscription"],
    "Government" => ["Grants & Subsidies"],
    "Knowledge & Research" => ["Licensing"],
    "Practice Management" => ["Subscription"],
    "Marketplace and ALSPs" => ["Transaction Fee", "Subscription"],
    "Unknown" => ["Other"]
  }.freeze

  CANONICAL_TARGET_CLIENTS = MethodologyHelper::TARGET_CLIENTS.map { |row| row[:name] }.freeze
  CANONICAL_CATEGORY_NAMES = (
    MethodologyHelper::PRIMARY_CATEGORIES.map { |row| row[:name] } +
    MethodologyHelper::PROPOSED_PRIMARY_CATEGORIES.map { |row| row[:name] }
  ).uniq.freeze

  def self.canonical_target_client_names(raw)
    return [] if raw.blank?

    raw.to_s.split(/,\s*/).filter_map do |segment|
      canonical_target_client_name(segment)
    end.uniq
  end

  def self.canonical_target_client_name(raw)
    cleaned = raw.to_s.strip
    return nil if cleaned.blank? || cleaned.casecmp("unknown").zero?

    return cleaned if CANONICAL_TARGET_CLIENTS.include?(cleaned)

    alias_target = TARGET_CLIENT_ALIASES[cleaned.downcase]
    return alias_target if alias_target.present?

    CANONICAL_TARGET_CLIENTS.find { |name| name.casecmp(cleaned).zero? }
  end

  def self.find_target_client(raw)
    name = canonical_target_client_name(raw)
    return nil if name.blank?

    TargetClient.find_by(name: name)
  end

  def self.find_target_clients(raw)
    canonical_target_client_names(raw).filter_map { |name| TargetClient.find_by(name: name) }.uniq
  end

  def self.canonical_category_name(raw)
    cleaned = raw.to_s.split("-").first.to_s.strip
    return "Unknown" if cleaned.blank?

    return cleaned if CANONICAL_CATEGORY_NAMES.include?(cleaned)

    CANONICAL_CATEGORY_NAMES.find { |name| name.casecmp(cleaned).zero? } || "Unknown"
  end

  def self.find_category(raw)
    Category.find_by(name: canonical_category_name(raw))
  end

  def self.canonical_revenue_model_names(raw)
    names = Array(raw).flat_map { |value| value.to_s.split(/[,;]/).map(&:strip) }.reject(&:blank?)
    names = [raw.to_s.strip] if names.empty? && raw.present?
    names.flat_map { |name| LEGACY_REVENUE_MODEL_MAP.fetch(name, [name]) }.uniq & MethodologyHelper::REVENUE_MODEL_NAMES
  end

  def self.find_revenue_models(raw)
    canonical_revenue_model_names(raw).filter_map { |name| BusinessModel.find_by(name: name) }.uniq
  end
end
