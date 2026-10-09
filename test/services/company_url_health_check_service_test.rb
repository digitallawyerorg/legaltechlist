require "test_helper"
require "minitest/mock"
require "net/http"

class CompanyUrlHealthCheckServiceTest < ActiveSupport::TestCase
  setup do
    @company = companies(:one)
    @company.update_columns(status: "active", main_url: "http://example.com", url_status: nil, url_status_code: nil, url_checked_at: nil, url_health: nil)
  end

  def response(klass, code, location: nil)
    resp = klass.new("1.1", code, "")
    resp["location"] = location if location
    resp
  end

  def run_check(fake)
    service = CompanyUrlHealthCheckService.new(company: @company)
    service.stub(:request, fake) { service.call }
    @company.reload
  end

  test "records ok on a successful response" do
    result = run_check(response(Net::HTTPOK, "200"))
    assert_equal Company::URL_STATUS_OK, @company.url_status
    assert_equal 200, @company.url_status_code
    assert_equal 0, @company.url_consecutive_failures
    assert @company.url_checked_at.present?
    assert_equal Company::URL_STATUS_OK, result["url_status"]
  end

  test "treats a 403 bot-block as unknown, not broken" do
    run_check(response(Net::HTTPForbidden, "403"))
    assert_equal Company::URL_STATUS_UNKNOWN, @company.url_status
    assert_equal 0, @company.url_consecutive_failures
    assert_equal "bot_blocked", @company.url_health["reason_code"]
  end

  test "classifies reason_code by cause (dns, timeout, http status, tls, server error)" do
    run_check(response(Net::HTTPServiceUnavailable, "503"))
    assert_equal "server_error", @company.url_health["reason_code"]

    run_check(response(Net::HTTPNotFound, "404"))
    assert_equal "http_404", @company.url_health["reason_code"]

    service = CompanyUrlHealthCheckService.new(company: @company)
    service.stub(:request, ->(_uri, _method, **) { raise SocketError, "getaddrinfo failed" }) { service.call }
    assert_equal "dns_failure", @company.reload.url_health["reason_code"]

    service = CompanyUrlHealthCheckService.new(company: @company)
    service.stub(:request, ->(_uri, _method, **) { raise Net::OpenTimeout, "timed out" }) { service.call }
    assert_equal "timeout", @company.reload.url_health["reason_code"]
  end

  test "derive_reason_code classifies historical free-text rows without a stored code" do
    assert_equal "bot_blocked", CompanyUrlHealthCheckService.derive_reason_code(url_status: "unknown", status_code: 403, reason: "server responded 403 (access-restricted)")
    assert_equal "dns_failure", CompanyUrlHealthCheckService.derive_reason_code(url_status: "broken", status_code: nil, reason: "SocketError: getaddrinfo failed")
    assert_equal "tls_untrusted", CompanyUrlHealthCheckService.derive_reason_code(url_status: "unknown", status_code: 200, reason: "reachable but TLS cert not trusted (HTTP 200)")
    assert_equal "http_410", CompanyUrlHealthCheckService.derive_reason_code(url_status: "broken", status_code: 410, reason: "HTTP 410")
    assert_equal "ok", CompanyUrlHealthCheckService.derive_reason_code(url_status: "ok", status_code: 200, reason: nil)
  end

  def run_redirect_check(to:)
    responses = { "example.com" => response(Net::HTTPMovedPermanently, "301", location: to) }
    fake = ->(uri, _method, **) { responses.fetch(uri.host.sub(/\Awww\./, ""), response(Net::HTTPOK, "200")) }
    service = CompanyUrlHealthCheckService.new(company: @company)
    service.stub(:request, fake) { service.call }
    @company.reload
  end

  test "a redirect to a gambling host is broken at once, not ok" do
    run_redirect_check(to: "https://losari88gacor.com/")
    assert_equal Company::URL_STATUS_BROKEN, @company.url_status
    assert_equal "suspected_hijack", @company.url_health["reason_code"]
    assert_equal "https://losari88gacor.com/", @company.url_health["final_url"]
  end

  test "a redirect to another brand's domain is flagged for review rather than ok" do
    run_redirect_check(to: "https://www.ekie.co/")
    assert_equal Company::URL_STATUS_UNKNOWN, @company.url_status
    assert_equal "offsite_redirect", @company.url_health["reason_code"]
    assert_equal 0, @company.url_consecutive_failures
  end

  test "a redirect to the same brand on another TLD or subdomain stays ok" do
    run_redirect_check(to: "https://example.io/home")
    assert_equal Company::URL_STATUS_OK, @company.url_status

    run_redirect_check(to: "https://app.example.com/")
    assert_equal Company::URL_STATUS_OK, @company.url_status
  end

  test "only escalates to broken after consecutive failures" do
    run_check(response(Net::HTTPNotFound, "404"))
    assert_equal Company::URL_STATUS_UNKNOWN, @company.url_status
    assert_equal 1, @company.url_consecutive_failures

    run_check(response(Net::HTTPNotFound, "404"))
    assert_equal Company::URL_STATUS_BROKEN, @company.url_status
    assert_equal 2, @company.url_consecutive_failures
    assert_equal 404, @company.url_status_code
  end

  test "a success resets the failure counter" do
    run_check(response(Net::HTTPNotFound, "404"))
    run_check(response(Net::HTTPNotFound, "404"))
    assert_equal Company::URL_STATUS_BROKEN, @company.url_status

    run_check(response(Net::HTTPOK, "200"))
    assert_equal Company::URL_STATUS_OK, @company.url_status
    assert_equal 0, @company.url_consecutive_failures
  end

  test "connection errors count as failures" do
    service = CompanyUrlHealthCheckService.new(company: @company)
    raiser = ->(_uri, _method, **) { raise SocketError, "getaddrinfo failed" }
    service.stub(:request, raiser) { service.call }
    @company.reload
    assert_equal Company::URL_STATUS_UNKNOWN, @company.url_status
    assert_equal 1, @company.url_consecutive_failures
    assert_match(/SocketError/, @company.url_health["reason"])
  end

  test "5xx responses are inconclusive, not failures" do
    run_check(response(Net::HTTPServiceUnavailable, "503"))
    assert_equal Company::URL_STATUS_UNKNOWN, @company.url_status
    assert_equal 0, @company.url_consecutive_failures
    assert_equal 503, @company.url_status_code
  end

  test "a TLS cert error where the host still answers is treated as reachable" do
    service = CompanyUrlHealthCheckService.new(company: @company)
    # Verified request raises a cert error; the verify-disabled retry succeeds.
    fake = lambda do |_uri, _method, verify: true|
      raise OpenSSL::SSL::SSLError, "certificate verify failed" if verify

      response(Net::HTTPOK, "200")
    end
    service.stub(:request, fake) { service.call }
    @company.reload
    assert_equal Company::URL_STATUS_UNKNOWN, @company.url_status
    assert_equal 0, @company.url_consecutive_failures
    assert_match(/TLS cert not trusted/, @company.url_health["reason"])
  end

  test "a TLS cert error on a host that is truly down counts as a failure" do
    service = CompanyUrlHealthCheckService.new(company: @company)
    fake = lambda do |_uri, _method, verify: true|
      raise OpenSSL::SSL::SSLError, "certificate verify failed" if verify

      raise SocketError, "getaddrinfo failed"
    end
    service.stub(:request, fake) { service.call }
    @company.reload
    assert_equal Company::URL_STATUS_UNKNOWN, @company.url_status
    assert_equal 1, @company.url_consecutive_failures
    assert_match(/SSLError/, @company.url_health["reason"])
  end

  test "does not change lifecycle status" do
    run_check(response(Net::HTTPNotFound, "404"))
    run_check(response(Net::HTTPNotFound, "404"))
    assert_equal "active", @company.status
  end

  test "invalid main_url is recorded as unknown without a request" do
    @company.update_columns(main_url: "n/a")
    service = CompanyUrlHealthCheckService.new(company: @company)
    result = service.call
    @company.reload
    assert_equal "invalid_url", result["result"]
    assert_equal Company::URL_STATUS_UNKNOWN, @company.url_status
  end

  test "url_check_due excludes recently checked and resolved-status companies" do
    @company.update_columns(url_checked_at: 1.day.ago)
    assert_not_includes Company.url_check_due(30.days).to_a, @company

    @company.update_columns(url_checked_at: 60.days.ago)
    assert_includes Company.url_check_due(30.days).to_a, @company

    @company.update_columns(status: "acquired")
    assert_not_includes Company.url_check_due(30.days).to_a, @company
  end
end
