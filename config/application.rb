require_relative 'boot'
require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Legaltechlist
  class Application < Rails::Application
    # Initialize configuration defaults for Rails 8.
    config.load_defaults 8.0

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    config.time_zone = 'UTC'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    config.i18n.default_locale = :en

    config.ssl_options = { hsts: { subdomains: true } }
    config.action_mailer.perform_caching = false

    # Keep your custom configurations
    config.twitter_list_url = ENV['TWITTER_LIST_URL'] || "https://twitter.com/CodeX_Law/lists/legal-tech-companies"

    config.active_support.to_time_preserves_timezone = :zone
  end
end
