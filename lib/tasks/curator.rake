namespace :curator do
  desc "Create (or confirm) the Claude Tag curator AdminUser and print connector setup notes"
  task setup: :environment do
    email = Mcp::CuratorActor.email
    user = AdminUser.find_or_initialize_by(email: email)
    created = user.new_record?

    if created
      password = ENV["MCP_CURATOR_ADMIN_PASSWORD"].presence || SecureRandom.hex(24)
      user.password = password
      user.password_confirmation = password
      user.save!
    end

    puts "Curator admin user: #{email} (#{created ? 'created' : 'already exists'})"
    puts "Temporary password: #{password}" if created
    puts ""
    puts "Next steps:"
    puts "  1. Set MCP_CURATOR_TOKEN to a strong secret (used as the connector bearer token)."
    puts "  2. Optional overrides: MCP_CURATOR_EMAIL, MCP_CURATOR_AUTOPUBLISH,"
    puts "     MCP_CURATOR_MAX_DISCOVERY_LIMIT, MCP_CURATOR_MAX_CURATE_LIMIT,"
    puts "     MCP_CURATOR_MAX_DAILY_PUBLISH, MCP_CURATOR_SLACK_SUMMARY."
    puts "  3. Add the connector in Claude admin: URL https://<host>/mcp, scope to #rover-techindex."
    puts "  See docs/claude_tag_curator.md for the full guide."
  end
end
