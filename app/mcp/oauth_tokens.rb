require "jwt"

module Mcp
  # Stateless OAuth 2.1 token helpers for the curator connector.
  # Authorization codes, access tokens, and refresh tokens are all signed JWTs
  # (HS256), so no database tables are needed. PKCE (S256) is required.
  module OauthTokens
    ALGORITHM = "HS256".freeze
    SCOPE = "curator".freeze
    CODE_TTL = 600          # 10 minutes
    ACCESS_TTL = 3_600      # 1 hour
    REFRESH_TTL = 30 * 24 * 3_600 # 30 days

    class Error < StandardError; end

    module_function

    def secret
      ENV["MCP_OAUTH_SECRET"].presence || Rails.application.secret_key_base
    end

    def issue_code(client_id:, redirect_uri:, code_challenge:, subject:, resource:, issuer:)
      encode(
        "typ" => "code",
        "cid" => client_id,
        "ruri" => redirect_uri,
        "cc" => code_challenge,
        "sub" => subject.to_s,
        "aud" => resource,
        "iss" => issuer,
        "exp" => now + CODE_TTL
      )
    end

    def issue_access(subject:, resource:, issuer:)
      encode(
        "typ" => "access",
        "sub" => subject.to_s,
        "aud" => resource,
        "iss" => issuer,
        "scope" => SCOPE,
        "exp" => now + ACCESS_TTL
      )
    end

    def issue_refresh(subject:, client_id:, resource:, issuer:)
      encode(
        "typ" => "refresh",
        "sub" => subject.to_s,
        "cid" => client_id,
        "aud" => resource,
        "iss" => issuer,
        "exp" => now + REFRESH_TTL
      )
    end

    # Returns the decoded payload for a valid token of the expected type, or nil.
    def verify(token, type:, resource:, issuer:)
      return nil if token.blank?

      payload = decode(token)
      return nil unless payload["typ"] == type
      return nil unless payload["iss"] == issuer
      return nil unless payload["aud"] == resource

      payload
    rescue JWT::DecodeError, Error
      nil
    end

    def pkce_matches?(verifier, challenge)
      return false if verifier.blank? || challenge.blank?

      computed = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier.to_s), padding: false)
      ActiveSupport::SecurityUtils.secure_compare(computed, challenge.to_s)
    end

    def encode(payload)
      JWT.encode(payload.merge("iat" => now, "jti" => SecureRandom.uuid), secret, ALGORITHM)
    end

    def decode(token)
      JWT.decode(token, secret, true, { algorithm: ALGORITHM }).first
    end

    def now
      Time.current.to_i
    end
  end
end
