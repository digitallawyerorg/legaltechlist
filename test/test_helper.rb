ENV['RAILS_ENV'] ||= 'test'
ENV["DESCRIPTION_DRAFTS_USE_LLM"] ||= "false"
ENV["PROPOSAL_WEB_SEARCH_USE_RESPONSES"] ||= "false"
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'geocoder'

Geocoder.configure(lookup: :test, timeout: 1)
Geocoder::Lookup::Test.set_default_stub([{ 'latitude' => 37.7749, 'longitude' => -122.4194 }])

class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Add more helper methods to be used by all tests here...
end
