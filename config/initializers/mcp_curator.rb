require "mcp"

# The Claude Tag curator connector lives under the `Mcp` namespace in `app/mcp`.
# Defining the namespace here (and registering it as non-reloadable) lets Zeitwerk
# map `app/mcp/foo.rb` to `Mcp::Foo` instead of top-level `Foo`.
module Mcp; end

Rails.autoloaders.main.push_dir(Rails.root.join("app/mcp"), namespace: Mcp)

MCP.configure do |config|
  config.exception_reporter = lambda do |exception, server_context|
    Rails.logger.debug("[CuratorMCP] #{exception.class}: #{exception.message} (context: #{server_context.inspect})")
  end
end
