module Mcp
  # The person behind a curator request. Every MCP write is made as the shared curator
  # account (Mcp::CuratorActor), so without this the audit could not say which human's
  # connector made a change — two curators' rounds were indistinguishable.
  class Current < ActiveSupport::CurrentAttributes
    attribute :operator

    def self.operator_email
      operator&.email
    end
  end
end
