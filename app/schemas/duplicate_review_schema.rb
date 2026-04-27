class DuplicatePairReviewSchema < RubyLLM::Schema
  integer :company_id, description: "Primary company id."
  integer :candidate_company_id, description: "Compared candidate company id."
  string :relationship, enum: %w[duplicate rebrand related distinct], description: "Best relationship between the two company records."
  string :confidence, enum: %w[low medium high], description: "Confidence in the relationship assessment."
  array :reasons, of: :string, description: "Specific reasons supporting the relationship."
  array :recommended_actions, of: :string, description: "Human review actions; never automatic merge/delete."
end

class DuplicateReviewSchema < RubyLLM::Schema
  SCHEMA_VERSION = "2026-04-26.1".freeze

  string :overall_recommendation, enum: %w[needs_human_review likely_duplicate_group likely_rebrand_group related_entities likely_distinct], description: "Overall group-level recommendation."
  array :pair_reviews, of: DuplicatePairReviewSchema, description: "Pairwise duplicate/rebrand/related/distinct assessments."
  array :unresolved_questions, of: :string, description: "Questions a human reviewer should resolve before any merge or data change."
  string :rationale, description: "Brief summary of the duplicate review."
  string :confidence, enum: %w[low medium high], description: "Confidence in the group-level recommendation."
end
