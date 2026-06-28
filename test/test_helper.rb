ENV['RAILS_ENV'] ||= 'test'
ENV["DESCRIPTION_DRAFTS_USE_LLM"] ||= "false"
ENV["PROPOSAL_WEB_SEARCH_USE_RESPONSES"] ||= "false"
ENV["USER_SUBMISSION_TRIAGE_USE_LLM"] ||= "false"
ENV["USER_SUGGESTION_INTERPRET_USE_LLM"] ||= "false"
ENV["USER_SUGGESTION_AUTO_APPLY"] ||= "false"
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'

class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Add more helper methods to be used by all tests here...
end
