module UserSuggestionIssueTypes
  KEYS = %w[
    incorrect_details
    status_outdated
    wrong_category
    broken_link
    funding_wrong
    suggest_reference
    something_else
  ].freeze

  def self.valid?(issue_type)
    KEYS.include?(issue_type.to_s)
  end
end
