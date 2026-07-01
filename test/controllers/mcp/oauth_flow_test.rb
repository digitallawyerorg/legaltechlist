require "test_helper"

module Mcp
  class OauthFlowTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    REDIRECT_URI = "https://claude.ai/api/mcp/auth_callback".freeze

    setup do
      @previous_token = ENV["MCP_CURATOR_TOKEN"]
      ENV["MCP_CURATOR_TOKEN"] = nil
    end

    teardown do
      ENV["MCP_CURATOR_TOKEN"] = @previous_token
    end

    test "protected resource metadata advertises the authorization server" do
      get "/.well-known/oauth-protected-resource"
      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "#{base}/mcp", body["resource"]
      assert_includes body["authorization_servers"], base
    end

    test "authorization server metadata exposes the OAuth endpoints" do
      get "/.well-known/oauth-authorization-server"
      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "#{base}/oauth/authorize", body["authorization_endpoint"]
      assert_equal "#{base}/oauth/token", body["token_endpoint"]
      assert_equal "#{base}/oauth/register", body["registration_endpoint"]
      assert_includes body["code_challenge_methods_supported"], "S256"
    end

    test "dynamic client registration accepts allowed redirect hosts" do
      post "/oauth/register", params: { redirect_uris: [REDIRECT_URI], client_name: "Claude" }.to_json,
                              headers: { "CONTENT_TYPE" => "application/json" }
      assert_response :created
      assert JSON.parse(response.body)["client_id"].present?
    end

    test "dynamic client registration rejects untrusted redirect hosts" do
      post "/oauth/register", params: { redirect_uris: ["https://evil.example/callback"] }.to_json,
                              headers: { "CONTENT_TYPE" => "application/json" }
      assert_response :bad_request
    end

    test "authorize requires an admin login" do
      get "/oauth/authorize", params: authorize_params
      assert_redirected_to new_admin_user_session_path
    end

    test "full authorization code + PKCE flow yields a working MCP access token" do
      sign_in admin_users(:one)

      get "/oauth/authorize", params: authorize_params
      assert_response :redirect
      location = URI.parse(response.location)
      assert_equal "claude.ai", location.host
      code = Rack::Utils.parse_query(location.query)["code"]
      assert code.present?
      assert_equal "xyz-state", Rack::Utils.parse_query(location.query)["state"]

      post "/oauth/token", params: {
        grant_type: "authorization_code",
        code: code,
        redirect_uri: REDIRECT_URI,
        client_id: client_id,
        code_verifier: verifier
      }
      assert_response :success
      tokens = JSON.parse(response.body)
      assert_equal "Bearer", tokens["token_type"]
      access = tokens["access_token"]
      assert access.present?
      assert tokens["refresh_token"].present?

      post "/mcp", params: rpc("tools/list"),
                   headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json", "Authorization" => "Bearer #{access}" }
      assert_response :success
      assert JSON.parse(response.body).dig("result", "tools").any?

      # Refresh token grant issues a fresh access token.
      post "/oauth/token", params: { grant_type: "refresh_token", refresh_token: tokens["refresh_token"], client_id: client_id }
      assert_response :success
      assert JSON.parse(response.body)["access_token"].present?
    end

    test "token exchange fails when the PKCE verifier is wrong" do
      sign_in admin_users(:one)
      get "/oauth/authorize", params: authorize_params
      code = Rack::Utils.parse_query(URI.parse(response.location).query)["code"]

      post "/oauth/token", params: {
        grant_type: "authorization_code",
        code: code,
        redirect_uri: REDIRECT_URI,
        client_id: client_id,
        code_verifier: "wrong-verifier"
      }
      assert_response :bad_request
      assert_equal "invalid_grant", JSON.parse(response.body)["error"]
    end

    private

    def base
      "http://www.example.com"
    end

    def verifier
      @verifier ||= SecureRandom.urlsafe_base64(48)
    end

    def challenge
      Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    end

    def client_id
      @client_id ||= SecureRandom.uuid
    end

    def authorize_params
      {
        response_type: "code",
        client_id: client_id,
        redirect_uri: REDIRECT_URI,
        code_challenge: challenge,
        code_challenge_method: "S256",
        state: "xyz-state"
      }
    end

    def rpc(method, params = {})
      { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json
    end
  end
end
