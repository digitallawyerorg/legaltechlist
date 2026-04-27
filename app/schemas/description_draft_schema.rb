class DescriptionDraftSchema < RubyLLM::Schema
  SCHEMA_VERSION = "2026-04-26.1".freeze

  string :proposed_description, description: "One neutral, factual TechIndex description sentence, 25 to 45 words."
  string :rationale, description: "Brief explanation of which evidence and limits shaped the draft."
  string :confidence, enum: %w[low medium high], description: "Confidence in the draft based on available evidence."
end
