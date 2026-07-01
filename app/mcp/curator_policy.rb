module Mcp
  # Central guardrail configuration for the curator connector: tiering kill-switch,
  # discovery/curation caps, and the daily auto-publish budget.
  module CuratorPolicy
    DEFAULT_SITE_URL = "https://techindex.law.stanford.edu".freeze

    module_function

    def autopublish_enabled?
      ENV.fetch("MCP_CURATOR_AUTOPUBLISH", "true") == "true"
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
