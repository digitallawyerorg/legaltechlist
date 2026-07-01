module Mcp
  # OAuth 2.1 authorization server for the curator connector (single-tenant).
  # Serves discovery metadata, dynamic client registration, an admin-gated
  # authorization endpoint (PKCE), and a token endpoint. Tokens are stateless
  # signed JWTs (see Mcp::OauthTokens).
  class OauthController < ApplicationController
    skip_before_action :verify_authenticity_token, only: %i[register token]
    before_action :authenticate_admin_user!, only: :authorize

    def protected_resource
      render json: {
        resource: resource,
        authorization_servers: [issuer],
        bearer_methods_supported: ["header"],
        scopes_supported: [Mcp::OauthTokens::SCOPE]
      }
    end

    def authorization_server
      render json: {
        issuer: issuer,
        authorization_endpoint: "#{issuer}/oauth/authorize",
        token_endpoint: "#{issuer}/oauth/token",
        registration_endpoint: "#{issuer}/oauth/register",
        response_types_supported: ["code"],
        grant_types_supported: %w[authorization_code refresh_token],
        code_challenge_methods_supported: ["S256"],
        token_endpoint_auth_methods_supported: ["none"],
        scopes_supported: [Mcp::OauthTokens::SCOPE]
      }
    end

    # Dynamic Client Registration (RFC 7591). Public clients only (PKCE), so no
    # client secret is issued. We don't persist clients: everything needed is
    # bound into the signed authorization code and validated at the token step.
    def register
      redirect_uris = Array(params[:redirect_uris])

      if redirect_uris.empty? || redirect_uris.any? { |uri| !Mcp::CuratorPolicy.allowed_redirect_uri?(uri) }
        return render json: { error: "invalid_redirect_uri", error_description: "redirect_uris must be on an allowed host" }, status: :bad_request
      end

      render json: {
        client_id: SecureRandom.uuid,
        client_id_issued_at: Time.current.to_i,
        redirect_uris: redirect_uris,
        token_endpoint_auth_method: "none",
        grant_types: %w[authorization_code refresh_token],
        response_types: ["code"],
        client_name: params[:client_name]
      }, status: :created
    end

    def authorize
      return authorize_error("unsupported_response_type") unless params[:response_type] == "code"
      return authorize_error("invalid_request", "code_challenge (S256) is required") unless params[:code_challenge].present? && params[:code_challenge_method] == "S256"
      return authorize_error("invalid_request", "client_id is required") if params[:client_id].blank?
      return authorize_error("invalid_request", "redirect_uri is not allowed") unless Mcp::CuratorPolicy.allowed_redirect_uri?(params[:redirect_uri])

      code = Mcp::OauthTokens.issue_code(
        client_id: params[:client_id],
        redirect_uri: params[:redirect_uri],
        code_challenge: params[:code_challenge],
        subject: current_admin_user.id,
        resource: resource,
        issuer: issuer
      )

      redirect_to(append_query(params[:redirect_uri], code: code, state: params[:state]), allow_other_host: true)
    end

    def token
      case params[:grant_type]
      when "authorization_code" then exchange_authorization_code
      when "refresh_token" then exchange_refresh_token
      else token_error("unsupported_grant_type")
      end
    end

    private

    def exchange_authorization_code
      payload = Mcp::OauthTokens.verify(params[:code], type: "code", resource: resource, issuer: issuer)
      return token_error("invalid_grant", "authorization code is invalid or expired") unless payload
      return token_error("invalid_grant", "client_id mismatch") unless payload["cid"] == params[:client_id]
      return token_error("invalid_grant", "redirect_uri mismatch") unless payload["ruri"] == params[:redirect_uri]
      return token_error("invalid_grant", "PKCE verification failed") unless Mcp::OauthTokens.pkce_matches?(params[:code_verifier], payload["cc"])

      render_tokens(subject: payload["sub"], client_id: payload["cid"])
    end

    def exchange_refresh_token
      payload = Mcp::OauthTokens.verify(params[:refresh_token], type: "refresh", resource: resource, issuer: issuer)
      return token_error("invalid_grant", "refresh token is invalid or expired") unless payload
      return token_error("invalid_grant", "client_id mismatch") if params[:client_id].present? && payload["cid"] != params[:client_id]

      render_tokens(subject: payload["sub"], client_id: payload["cid"])
    end

    def render_tokens(subject:, client_id:)
      render json: {
        access_token: Mcp::OauthTokens.issue_access(subject: subject, resource: resource, issuer: issuer),
        token_type: "Bearer",
        expires_in: Mcp::OauthTokens::ACCESS_TTL,
        refresh_token: Mcp::OauthTokens.issue_refresh(subject: subject, client_id: client_id, resource: resource, issuer: issuer),
        scope: Mcp::OauthTokens::SCOPE
      }
    end

    def authorize_error(error, description = nil)
      render json: { error: error, error_description: description }.compact, status: :bad_request
    end

    def token_error(error, description = nil)
      render json: { error: error, error_description: description }.compact, status: :bad_request
    end

    def issuer
      Mcp::CuratorPolicy.issuer(request)
    end

    def resource
      Mcp::CuratorPolicy.resource(request)
    end

    def append_query(uri, extra)
      parsed = URI.parse(uri)
      pairs = URI.decode_www_form(parsed.query || "")
      extra.compact.each { |key, value| pairs << [key.to_s, value] }
      parsed.query = URI.encode_www_form(pairs)
      parsed.to_s
    end
  end
end
