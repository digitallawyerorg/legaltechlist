module Mcp
  # Builds a stateless MCP::Server instance (one per request) with the full
  # curator toolset registered.
  module CuratorServer
    module_function

    def build(actor: "claude_tag")
      MCP::Server.new(
        name: "techindex_curator",
        title: "CodeX TechIndex Curator",
        version: "1.0.0",
        tools: Mcp::Tools.all,
        server_context: { actor: actor }
      )
    end
  end
end
