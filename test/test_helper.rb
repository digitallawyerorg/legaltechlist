ENV['RAILS_ENV'] ||= 'test'
ENV["DESCRIPTION_DRAFTS_USE_LLM"] ||= "false"
ENV["PROPOSAL_WEB_SEARCH_USE_RESPONSES"] ||= "false"
ENV["USER_SUBMISSION_TRIAGE_USE_LLM"] ||= "false"
ENV["USER_SUGGESTION_INTERPRET_USE_LLM"] ||= "false"
ENV["USER_SUGGESTION_AUTO_APPLY"] ||= "false"
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'

# Never deliver real Slack messages from the test suite. Delivery is only enabled
# inside `with_slack_delivery { ... }`, for tests that explicitly exercise Slack.
module SlackNotifierTestSilence
  def post_message(*args, **kwargs)
    Thread.current[:allow_slack_delivery] ? super : nil
  end

  def post_thread(*args, **kwargs)
    Thread.current[:allow_slack_delivery] ? super : nil
  end
end
SlackNotifier.singleton_class.prepend(SlackNotifierTestSilence)

class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Allow real SlackNotifier delivery within the block (still respects env config).
  def with_slack_delivery
    previous = Thread.current[:allow_slack_delivery]
    Thread.current[:allow_slack_delivery] = true
    yield
  ensure
    Thread.current[:allow_slack_delivery] = previous
  end

  # Add more helper methods to be used by all tests here...
end
