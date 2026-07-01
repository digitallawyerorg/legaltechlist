require "test_helper"

module Mcp
  class CuratorControllerTest < ActionDispatch::IntegrationTest
    setup do
      @previous_token = ENV["MCP_CURATOR_TOKEN"]
      ENV["MCP_CURATOR_TOKEN"] = "test-secret"
    end

    teardown do
      ENV["MCP_CURATOR_TOKEN"] = @previous_token
    end

    test "rejects requests without a bearer token and points to OAuth metadata" do
      post "/mcp", params: rpc("tools/list"), headers: request_headers(authorization: nil)
      assert_response :unauthorized
      assert_match %r{oauth-protected-resource}, response.headers["WWW-Authenticate"].to_s
    end

    test "rejects requests with the wrong bearer token" do
      post "/mcp", params: rpc("tools/list"), headers: request_headers(authorization: "Bearer nope")
      assert_response :unauthorized
    end

    test "still returns 401 (not 503) when no static token is configured" do
      ENV["MCP_CURATOR_TOKEN"] = ""
      post "/mcp", params: rpc("tools/list"), headers: request_headers(authorization: "Bearer anything")
      assert_response :unauthorized
    end

    test "lists curator tools for a request with the static token" do
      post "/mcp", params: rpc("tools/list"), headers: request_headers
      assert_response :success

      names = JSON.parse(response.body).dig("result", "tools").map { |tool| tool["name"] }
      assert_includes names, "search_companies"
      assert_includes names, "discover_companies"
      assert_includes names, "curate_pending"
      assert_includes names, "apply_safe_fields"
    end

    private

    def request_headers(authorization: "Bearer test-secret")
      headers = { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      headers["Authorization"] = authorization if authorization
      headers
    end

    def rpc(method, params = {})
      { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json
    end
  end
end
