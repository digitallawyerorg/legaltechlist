# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = '1.0'

# Add additional assets to the asset load path.
Rails.application.config.assets.paths << Rails.root.join('node_modules')
Rails.application.config.assets.paths << Rails.root.join('vendor', 'javascript')

# Precompile additional assets.
Rails.application.config.assets.precompile += %w( 
  companies.js 
  application.js
)

# Enable compiling assets on deploy
Rails.application.config.assets.compile = true

# Initialize configuration defaults
Rails.application.config.assets.initialize_on_precompile = false
