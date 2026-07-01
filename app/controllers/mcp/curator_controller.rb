module Mcp
  # Remote MCP endpoint for the Claude Tag curator connector.
  # Stateless Streamable HTTP (JSON responses). Authenticated with an OAuth 2.1
  # access token (see Mcp::OauthController) or an optional static bearer token.
  class CuratorController < ActionController::API
    before_action :authenticate_curator!

    def handle
      server = Mcp::CuratorServer.build(actor: "claude_tag")
      transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true, enable_json_response: true)

      rewind_request_body!
      status, headers, body = transport.handle_request(Rack::Request.new(request.env))

      headers.each { |key, value| response.headers[key] = value unless key.to_s.casecmp?("content-type") }
      payload = Array(body).first

      if payload.nil?
        head status
      else
        render json: payload, status: status
      end
    end

    private

    def rewind_request_body!
      input = request.env["rack.input"]
      input.rewind if input.respond_to?(:rewind)
    rescue StandardError
      nil
    end

    def authenticate_curator!
      return if valid_oauth_token? || valid_static_token?

      metadata_url = "#{Mcp::CuratorPolicy.issuer(request)}/.well-known/oauth-protected-resource"
      response.headers["WWW-Authenticate"] = %(Bearer error="invalid_token", resource_metadata="#{metadata_url}")
      render json: { error: "Unauthorized" }, status: :unauthorized
    end

    # OAuth 2.1 access token issued by Mcp::OauthController (the primary path for
    # the Claude connector).
    def valid_oauth_token?
      Mcp::OauthTokens.verify(
        bearer_token,
        type: "access",
        resource: Mcp::CuratorPolicy.resource(request),
        issuer: Mcp::CuratorPolicy.issuer(request)
      ).present?
    end

    # Optional static bearer token, handy for MCP Inspector / curl testing and as
    # a break-glass credential. Only enabled when MCP_CURATOR_TOKEN is set.
    def valid_static_token?
      expected = ENV["MCP_CURATOR_TOKEN"].to_s
      return false if expected.blank?

      token = bearer_token
      token.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)
    end

    def bearer_token
      request.authorization.to_s[/\ABearer\s+(.+)\z/i, 1]
    end
  end
end
