require "test_helper"
require "minitest/mock"

class SiteEvidenceFetcherServiceTest < ActiveSupport::TestCase
  HTML = <<~HTML.freeze
    <html><head><title>Pactolane — Contract lifecycle management</title>
    <meta name="description" content="CLM for legal and procurement teams.">
    <script>var tracking = 1;</script></head>
    <body><nav>Home Pricing</nav><h1>Contract lifecycle management</h1>
    <p>Pactolane centralizes contracts, supports approval workflows and eIDAS e-signature.</p>
    <footer>Imprint © 2026 Pactolane Holdings Ltd</footer></body></html>
  HTML

  def with_fetch_enabled
    previous = ENV["PROPOSAL_SITE_FETCH"]
    ENV["PROPOSAL_SITE_FETCH"] = "true"
    yield
  ensure
    ENV["PROPOSAL_SITE_FETCH"] = previous
  end

  # Stubs the single network seam, keyed by URL, so no test touches the network.
  def run_fetch(outcomes, **kwargs)
    service = SiteEvidenceFetcherService.new(**kwargs)
    service.define_singleton_method(:perform_request) do |uri|
      outcomes[uri.to_s] || outcomes[:default] || raise(SocketError, "getaddrinfo")
    end
    with_fetch_enabled { service.call }
  end

  def ok_response(body)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) { body }
    response
  end

  def status_response(klass, code)
    response = klass.new("1.1", code, "")
    response.define_singleton_method(:body) { "" }
    response
  end

  test "extracts title and body text from the company's own page" do
    payload = run_fetch({ default: ok_response(HTML) }, main_url: "https://pactolane.com")
    page = payload["pages"].find { |p| p["label"] == "website" }

    assert_equal "fetched", page["status"]
    assert_equal "Pactolane — Contract lifecycle management", page["title"]
    assert_includes page["text"], "eIDAS e-signature"
    assert_includes page["text"], "CLM for legal and procurement teams."
    refute_includes page["text"], "var tracking", "scripts must not leak into evidence text"
    refute_includes page["text"], "Pricing", "nav chrome is stripped"
  end

  # The footer is where the operating company gets named when the product branding
  # does not. Stripping it left DescriptionVerificationAgent with no entity to
  # verify against, so it returned MANUAL_REVIEW with no verified_company.
  FOOTER_ENTITY_HTML = <<~HTML.freeze
    <html><head><title>Lexvane</title></head>
    <body><nav>Home Pricing Careers</nav><h1>Lexvane</h1>
    <p>Lexvane automates matter intake for in-house teams.</p>
    <footer>© 2026 Foo Holdings Ltd. All rights reserved.</footer></body></html>
  HTML

  test "keeps footer text so a copyright line naming the legal entity reaches the agent" do
    payload = run_fetch({ default: ok_response(FOOTER_ENTITY_HTML) }, main_url: "https://lexvane.com")
    page = payload["pages"].find { |p| p["label"] == "website" }

    assert_equal "fetched", page["status"]
    assert_includes page["text"], "© 2026 Foo Holdings Ltd",
                    "the footer names the operating company when product branding does not"
    refute_includes page["text"], "Careers", "nav chrome is still stripped"
  end

  test "records a LinkedIn sign-in wall as blocked, not as a failure to try" do
    payload = run_fetch(
      { "https://www.linkedin.com/company/pactolane/" => status_response(Net::HTTPForbidden, "403"), default: ok_response(HTML) },
      main_url: "https://pactolane.com", linkedin_url: "https://www.linkedin.com/company/pactolane/"
    )
    page = payload["pages"].find { |p| p["label"] == "linkedin" }

    assert_equal "blocked", page["status"]
    assert_equal "linkedin_requires_sign_in", page["reason"]
  end

  test "follows a redirect and reports the domain it landed on" do
    payload = run_fetch(
      {
        "https://leahai.com/" => status_response(Net::HTTPMovedPermanently, "301").tap { |r| r["location"] = "https://contractpodai.com/" },
        "https://contractpodai.com/" => ok_response(HTML)
      },
      main_url: "https://leahai.com/"
    )
    page = payload["pages"].find { |p| p["label"] == "website" }

    assert_equal "fetched", page["status"]
    assert_equal "https://contractpodai.com/", page["final_url"],
                 "the resolved domain is what links a rebrand to its existing entry"
  end

  test "classifies unreachable and erroring hosts without raising" do
    dns = run_fetch({}, main_url: "https://nope.invalid")
    assert_equal "error", dns["pages"].first["status"]
    assert_equal "dns_failure", dns["pages"].first["reason"]

    gone = run_fetch({ default: status_response(Net::HTTPNotFound, "404") }, main_url: "https://pactolane.com")
    assert_equal "http_404", gone["pages"].first["reason"]
  end

  test "a missing /about is an absence, not a retrieval failure" do
    payload = run_fetch(
      { "https://pactolane.com/about" => status_response(Net::HTTPNotFound, "404"), default: ok_response(HTML) },
      main_url: "https://pactolane.com"
    )
    about = payload["pages"].find { |p| p["label"] == "website_about" }

    assert_equal "skipped", about["status"], "we guessed this URL, so a 404 is not a finding"
    assert_equal "no_such_page", about["reason"]
  end

  test "reports skipped rather than silently omitting when fetching is off" do
    previous = ENV["PROPOSAL_SITE_FETCH"]
    ENV["PROPOSAL_SITE_FETCH"] = "false"
    payload = SiteEvidenceFetcherService.call(main_url: "https://pactolane.com")

    assert_equal "disabled", payload["mode"]
    assert_equal ["skipped"], payload["pages"].map { |p| p["status"] }.uniq
  ensure
    ENV["PROPOSAL_SITE_FETCH"] = previous
  end

  test "evidence_text yields only retrieved pages, attributed to their URL" do
    payload = run_fetch(
      { "https://www.linkedin.com/company/x/" => status_response(Net::HTTPForbidden, "403"), default: ok_response(HTML) },
      main_url: "https://pactolane.com", linkedin_url: "https://www.linkedin.com/company/x/"
    )
    blocks = SiteEvidenceFetcherService.evidence_text(payload)

    assert blocks.any?
    assert blocks.all? { |block| block.start_with?("SOURCE https://") }
    refute blocks.any? { |block| block.include?("linkedin.com") }
  end
end
