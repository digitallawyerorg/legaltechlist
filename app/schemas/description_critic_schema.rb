class DescriptionCriticSchema < RubyLLM::Schema
  SCHEMA_VERSION = "2026-04-26.1".freeze

  string :verdict, enum: %w[pass revise reject], description: "Whether the proposed description is safe for human review, needs revision, or should be rejected."
  array :issues, of: :string, description: "Specific quality issues found in the proposed description."
  string :rationale, description: "Brief explanation for the verdict."
  string :suggested_revision, description: "Safer replacement sentence if possible from the evidence, otherwise an empty string."
  string :confidence, enum: %w[low medium high], description: "Confidence in the critique based on available evidence."
end
