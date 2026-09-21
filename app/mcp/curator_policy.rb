module Mcp
  # Central guardrail configuration for the curator connector: tiering kill-switch,
  # discovery/curation caps, and the daily auto-publish budget.
  module CuratorPolicy
    DEFAULT_SITE_URL = "https://techindex.law.stanford.edu".freeze

    module_function

    def autopublish_enabled?
      ENV.fetch("MCP_CURATOR_AUTOPUBLISH", "true") == "true"
    end

    # Allow the curator to apply edits to EXISTING companies without a human,
    # separate from new-entry auto-publishing. Off by default: live-entry changes
    # are higher risk, so opt in only once the connector is trusted.
    def autoapply_updates_enabled?
      ENV.fetch("MCP_CURATOR_AUTOAPPLY_UPDATES", "false") == "true"
    end

    # Minimum self-reported confidence (0.0-1.0) required for any autonomous
    # publish/apply. This is an additional brake on top of the objective gates,
    # never a substitute for them.
    def min_confidence
      ENV.fetch("MCP_CURATOR_MIN_CONFIDENCE", "0.8").to_f
    end

    # Higher bar for externally-submitted proposals (public contribution/suggestion
    # forms), which are lower-trust and a common spam vector.
    def min_confidence_external
      ENV.fetch("MCP_CURATOR_MIN_CONFIDENCE_EXTERNAL", "0.9").to_f
    end

    def required_confidence(proposal = nil)
      proposal&.externally_submitted? ? min_confidence_external : min_confidence
    end

    def confidence_ok?(value, proposal = nil)
      return false if value.nil?

      value.to_f >= required_confidence(proposal)
    end

    def max_discovery_limit
      ENV.fetch("MCP_CURATOR_MAX_DISCOVERY_LIMIT", "25").to_i
    end

    def max_curate_limit
      ENV.fetch("MCP_CURATOR_MAX_CURATE_LIMIT", "100").to_i
    end

    def max_daily_publish
      ENV.fetch("MCP_CURATOR_MAX_DAILY_PUBLISH", "50").to_i
    end

    def slack_summary_enabled?
      ENV.fetch("MCP_CURATOR_SLACK_SUMMARY", "false") == "true"
    end

    def site_url
      ENV.fetch("SITE_URL", DEFAULT_SITE_URL)
    end

    DEFAULT_REDIRECT_HOSTS = %w[claude.ai claude.com console.anthropic.com localhost 127.0.0.1].freeze

    # OAuth issuer for the connector. Prefer an explicit env value so it stays
    # stable behind Heroku's proxy; otherwise derive it from the request.
    def issuer(request)
      ENV["MCP_OAUTH_ISSUER"].presence || request.base_url
    end

    def resource(request)
      "#{issuer(request)}/mcp"
    end

    # Host names this connector is served under. mcp 1.x validates the Host header
    # itself to block DNS rebinding, and ships only the loopback names; a deployed
    # endpoint has to name its own. Derived from the URLs the app already knows it
    # answers on, with MCP_ALLOWED_HOSTS for anything extra (a Heroku domain, a
    # staging host). Ports are dropped: the gem matches the bare name on any port.
    def allowed_request_hosts
      from_urls = [site_url, ENV["MCP_OAUTH_ISSUER"]].filter_map { |url| host_in(url) }
      configured = ENV["MCP_ALLOWED_HOSTS"].to_s.split(",").filter_map { |entry| entry.strip.presence }

      (from_urls + configured).uniq
    end

    def host_in(url)
      URI.parse(url.to_s).host
    rescue URI::InvalidURIError
      nil
    end

    def allowed_redirect_hosts
      configured = ENV["MCP_OAUTH_ALLOWED_REDIRECT_HOSTS"].to_s.split(",").map(&:strip).reject(&:blank?)
      (DEFAULT_REDIRECT_HOSTS + configured).uniq
    end

    def allowed_redirect_uri?(uri)
      parsed = URI.parse(uri.to_s)
      return false unless parsed.host
      return false unless %w[http https].include?(parsed.scheme)
      return false if parsed.scheme == "http" && !%w[localhost 127.0.0.1].include?(parsed.host)

      allowed_redirect_hosts.include?(parsed.host)
    rescue URI::InvalidURIError
      false
    end

    def published_today(admin_user)
      return 0 unless admin_user

      CompanyProposal.where(admin_user: admin_user, status: "published")
                     .where("approved_at >= ?", Time.current.beginning_of_day)
                     .count
    end

    def remaining_daily_publish_budget(admin_user)
      [max_daily_publish - published_today(admin_user), 0].max
    end
  end
end
