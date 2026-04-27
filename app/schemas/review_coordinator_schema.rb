class ReviewCoordinatorSchema < RubyLLM::Schema
  SCHEMA_VERSION = "2026-04-26.1".freeze

  string :status, enum: %w[ready_for_human_review needs_more_evidence needs_description_revision possible_duplicate do_not_publish], description: "Overall next review state for the company."
  array :reasons, of: :string, description: "Specific reasons supporting the status."
  array :disagreements, of: :string, description: "Agent disagreements or unresolved tensions that should remain visible to a human reviewer."
  array :recommended_actions, of: :string, description: "Concrete next actions for a human reviewer."
  string :confidence, enum: %w[low medium high], description: "Confidence in this coordination decision."
end
