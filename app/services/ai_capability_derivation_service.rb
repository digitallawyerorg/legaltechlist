class AiCapabilityDerivationService
  TIERS = %w[none ml genai agentic unknown].freeze

  AGENTIC_PATTERNS = /\b(agentic|autonomous agent|ai agent|multi-agent|agent workflow)\b/i
  GENAI_PATTERNS = /\b(generative ai|genai|gen ai|llm|large language model|gpt|chatbot)\b/i
  ML_PATTERNS = /\b(machine learning|deep learning|nlp|natural language processing|predictive)\b/i

  def self.call(company:)
    new(company: company).call
  end

  def self.derive_from_tag_names(tag_names)
    names = Array(tag_names).filter_map { |name| TagNormalizationService.canonical_name(name) }
    derive_from_names(names)
  end

  def self.derive_from_names(tag_names)
    return "none" if tag_names.empty?
    return "agentic" if tag_names.any? { |name| name.match?(AGENTIC_PATTERNS) }
    return "genai" if tag_names.any? { |name| name.match?(GENAI_PATTERNS) }
    return "ml" if tag_names.any? { |name| name.match?(ML_PATTERNS) }
    return "ml" if tag_names.any? { |name| TagNormalizationService.ai_related?(name) && name.match?(/\bmachine learning\b/) }

    tag_names.any? { |name| TagNormalizationService.ai_related?(name) } ? "ml" : "none"
  end

  def initialize(company:)
    @company = company
  end

  def call
    tag_names = company.tags.map { |tag| TagNormalizationService.canonical_name(tag.name) }.compact
    self.class.derive_from_names(tag_names)
  end

  private

  attr_reader :company
end
