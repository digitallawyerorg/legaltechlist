module Mcp
  # Resolves the dedicated AdminUser that all curator actions are attributed to,
  # so every write has a real actor in logs and the proposal/audit trail.
  module CuratorActor
    DEFAULT_EMAIL = "claude-curator@techindex".freeze

    module_function

    def email
      ENV.fetch("MCP_CURATOR_EMAIL", DEFAULT_EMAIL)
    end

    def find
      AdminUser.find_by(email: email)
    end

    def admin_user!
      find || raise("Curator admin user (#{email}) is missing. Run `bin/rails curator:setup` first.")
    end
  end
end
