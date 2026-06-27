class TaxonomyNormalizationService
  TARGET_CLIENT_ALIASES = {
    "individual consumers" => "Consumers",
    "individual consumer" => "Consumers",
    "consumer" => "Consumers",
    "consumers" => "Consumers",
    "in-house" => "Corporate Legal",
    "in house" => "Corporate Legal",
    "corporate" => "Corporate Legal",
    "legal service provider" => "Legal Service Providers",
    "legal service providers" => "Legal Service Providers",
    "law firm" => "Law Firms",
    "law firms" => "Law Firms",
    "government" => "Government",
    "legal education" => "Legal Education"
  }.freeze

  CANONICAL_TARGET_CLIENTS = MethodologyHelper::TARGET_CLIENTS.map { |row| row[:name] }.freeze

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

    match = CANONICAL_TARGET_CLIENTS.find { |name| name.casecmp(cleaned).zero? }
    match
  end

  def self.find_target_client(raw)
    name = canonical_target_client_name(raw)
    return nil if name.blank?

    TargetClient.find_by(name: name)
  end

  def self.find_revenue_models(raw_names)
    Array(raw_names).filter_map do |raw|
      name = raw.to_s.strip
      next if name.blank?

      BusinessModel.find_by(name: name) if MethodologyHelper::REVENUE_MODEL_NAMES.include?(name)
    end.uniq
  end
end
