class TagTaxonomyService
  # Canonical tag roots that duplicate Category, Revenue model, or Target client fields.
  REDUNDANT_CANONICAL_ROOTS = [
    "analytics", "automation", "compliance", "consumers", "contract management",
    "dispute resolution", "document management", "intellectual property",
    "knowledge management", "law firms", "legal research", "legal tech", "litigation",
    "marketplace", "online platform", "practice management", "saas"
  ].freeze

  def self.canonical_root_names
    @canonical_root_names ||= begin
      path = Rails.root.join("config/taxonomy/tag_aliases.yml")
      data = YAML.safe_load(File.read(path), permitted_classes: [], aliases: true) || {}
      data.keys.map { |name| TagNormalizationService.normalize_name(name) }.uniq
    end
  end

  def self.structured_canonical_terms
    @structured_canonical_terms ||= begin
      terms = []
      Category.pluck(:name).each { |name| terms.concat(structured_tokens(name)) }
      BusinessModel.pluck(:name).each { |name| terms.concat(structured_tokens(name)) }
      MethodologyHelper::REVENUE_MODEL_NAMES.each { |name| terms.concat(structured_tokens(name)) }
      TargetClient.pluck(:name).each { |name| terms.concat(structured_tokens(name)) }
      TaxonomyNormalizationService::CANONICAL_TARGET_CLIENTS.each { |name| terms.concat(structured_tokens(name)) }
      terms.flatten.compact.map { |token| TagNormalizationService.normalize_name(token) }.uniq
    end
  end

  def self.redundant_with_taxonomy?(raw)
    canonical = TagNormalizationService.canonical_name(raw)
    return false if canonical.blank?

    return true if REDUNDANT_CANONICAL_ROOTS.include?(canonical)
    return true if structured_canonical_terms.include?(canonical)

    fuzzy_structured_overlap?(canonical)
  end

  def self.discoverable_canonical_names
    @discoverable_canonical_names ||= canonical_root_names.reject { |name| redundant_with_taxonomy?(name) }.sort
  end

  def self.assignable?(raw)
    canonical = TagNormalizationService.canonical_name(raw)
    canonical.present? && discoverable_canonical_names.include?(canonical)
  end

  def self.filter_assignable(names)
    Array(names).filter_map { |name| TagNormalizationService.canonical_name(name) }
      .select { |name| discoverable_canonical_names.include?(name) }
      .uniq
  end

  def self.reset_cache!
    @canonical_root_names = nil
    @structured_canonical_terms = nil
    @discoverable_canonical_names = nil
    TagNormalizationService.instance_variable_set(:@alias_map, nil)
  end

  def self.structured_tokens(name)
    canonical = TagNormalizationService.canonical_name(name)
    normalized = TagNormalizationService.normalize_name(name)
    tokens = [canonical, normalized]
    normalized.to_s.split(/[&,\/]/).each { |part| tokens << TagNormalizationService.normalize_name(part) }
    tokens
  end
  private_class_method :structured_tokens

  def self.fuzzy_structured_overlap?(canonical)
    structured_canonical_terms.any? { |term| overlaps?(canonical, term) }
  end
  private_class_method :fuzzy_structured_overlap?

  def self.overlaps?(left, right)
    return false if left.blank? || right.blank?
    return true if left == right

    shorter, longer = [left, right].sort_by(&:length)
    return false if shorter.length < 4

    longer.include?(shorter)
  end
  private_class_method :overlaps?
end
