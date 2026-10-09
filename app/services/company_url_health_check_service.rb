require "net/http"
require "uri"
require "openssl"

# Probes a company's main_url and records a coarse health verdict used as a QC/
# maintenance signal for spotting companies that may have gone inactive. It never
# changes a company's lifecycle status — a broken URL is a soft indicator surfaced
# for curator review.
#
# Verdicts (stored on Company#url_status):
#   "ok"      – the site responded successfully (2xx, or a redirect chain ending 2xx)
#   "unknown" – the site is up but we can't confirm content health (401/403/429
#               bot-blocks, or a single transient failure below the flap threshold)
#   "broken"  – the URL is gone/unreachable across FAILURE_THRESHOLD consecutive checks
#
# A consecutive-failure counter (persisted in Company#url_health) prevents a single
# transient blip from flagging a live site.
class CompanyUrlHealthCheckService
  OPEN_TIMEOUT = 6
  READ_TIMEOUT = 10
  MAX_REDIRECTS = 5
  # Only escalate to "broken" after this many consecutive failing checks so a lone
  # transient outage does not flag a healthy company.
  FAILURE_THRESHOLD = 2
  USER_AGENT = "CodeX-TechIndex-LinkChecker/1.0 (+https://techindex.law.stanford.edu)".freeze

  # Response codes that mean "the server is up but is blocking automated access" —
  # common for Cloudflare/WAF-protected but perfectly live sites. Treated as
  # inconclusive, never as broken.
  BOT_BLOCK_CODES = [401, 403, 405, 406, 429].freeze

  # Hosts a lapsed legal-tech domain gets resold to. AdvantageLaw and Black Swan
  # Digital Forensics both read "ok" while redirecting to sites like losari88gacor.com.
  HIJACK_HOST_PATTERN = /gacor|slot|casino|togel|judi|poker|sbobet|jackpot|maxwin|bandar|betting|gambl/

  # Machine-readable reason_code taxonomy stored on Company#url_health["reason_code"].
  # Lets a curator separate "up but blocks crawlers" (fine) from "actually dead" (fix)
  # instead of leaving every "unknown" verdict in limbo.
  #   ok               – responded 2xx
  #   bot_blocked      – 401/403/405/406/429 (WAF/Cloudflare; almost always live)
  #   server_error     – 5xx (origin erroring; often transient)
  #   tls_untrusted    – reachable, but TLS cert not trusted (usually live behind a CDN)
  #   timeout          – open/read timeout
  #   dns_failure      – host does not resolve (strong "dead" signal)
  #   ssl_error        – TLS handshake failed even without verification
  #   redirect_error   – redirect loop or missing Location
  #   http_<status>    – any other client error, one code per status (e.g. http_404,
  #                      http_410 = strong "dead"; http_400/402/409 also seen)
  #   connection_reset – peer reset the connection mid-request
  #   connection_error – unclassified transport error (default fallback)
  #   offsite_redirect – answered 2xx, but only after redirecting to a different brand's
  #                      domain (a rebrand, an acquirer, or a lapsed domain): unknown
  #   suspected_hijack – the redirect lands on a gambling/spam host; broken at once,
  #                      because the profile is sending readers to it today
  # Additional codes emitted only under specific OS-level conditions (so they may not
  # appear in a given sample): connection_refused (Errno::ECONNREFUSED),
  # host_unreachable (Errno::EHOSTUNREACH/ENETUNREACH), invalid_url (no usable main_url).

  def self.call(**kwargs)
    new(**kwargs).call
  end

  # Best-effort classifier for pre-existing url_health rows that predate reason_code
  # (derives the code from the stored free-text reason + status_code, no network).
  def self.derive_reason_code(url_status:, status_code:, reason:)
    return Company::URL_STATUS_OK if url_status == Company::URL_STATUS_OK

    code = status_code.to_i
    text = reason.to_s.downcase
    return "invalid_url" if text.include?("no usable main_url")
    return "bot_blocked" if BOT_BLOCK_CODES.include?(code) || text.include?("access-restricted")
    return "tls_untrusted" if text.include?("tls cert not trusted")
    return "server_error" if code >= 500 || text.include?("server error")
    return "timeout" if text.include?("timeout")
    return "dns_failure" if text.include?("socketerror") || text.include?("getaddrinfo") || text.include?("failed to open tcp")
    return "connection_refused" if text.include?("econnrefused") || text.include?("connection refused")
    return "connection_reset" if text.include?("econnreset") || text.include?("connection reset")
    return "host_unreachable" if text.include?("ehostunreach") || text.include?("enetunreach") || text.include?("no route to host")
    return "ssl_error" if text.include?("ssl")
    return "redirect_error" if text.include?("redirect")
    return "http_#{code}" if code.between?(400, 499)

    "connection_error"
  end

  # reason_code for a company, preferring the stored value and falling back to a
  # derivation for historical rows.
  def self.reason_code_for(company)
    health = company.url_health.is_a?(Hash) ? company.url_health : {}
    health["reason_code"].presence || derive_reason_code(
      url_status: company.url_status,
      status_code: company.url_status_code,
      reason: health["reason"]
    )
  end

  # Convenience for the recurring sweep / rake task: enqueue up to `limit` due checks.
  def self.enqueue_due(limit: 200, cooldown: 30.days)
    ids = Company.url_check_due(cooldown).order(Arel.sql("url_checked_at ASC NULLS FIRST")).limit(limit).pluck(:id)
    ids.each { |id| CheckCompanyUrlHealthJob.perform_later(id) }
    ids
  end

  def initialize(company:)
    @company = company
  end

  def call
    url = normalized_url
    return record_invalid! if url.nil?

    outcome = probe(url)
    persist!(outcome)
    outcome.merge("company_id" => company.id, "url_status" => company.url_status)
  end

  private

  attr_reader :company

  def normalized_url
    raw = company.main_url.to_s.strip
    return nil if raw.blank? || raw.casecmp?("n/a") || raw.casecmp?("unknown")

    raw = "http://#{raw}" unless raw.match?(%r{\Ahttps?://}i)
    uri = URI.parse(raw)
    uri.is_a?(URI::HTTP) && uri.host.present? ? uri : nil
  rescue URI::InvalidURIError
    nil
  end

  # Follows redirects manually (HEAD first, GET fallback) so we can capture the final
  # URL and status. Returns a normalized outcome hash.
  def probe(uri, redirects_left = MAX_REDIRECTS, method: :head)
    response = request(uri, method)

    case response
    when Net::HTTPRedirection
      location = redirect_target(uri, response["location"])
      return failure_outcome("redirect loop or missing Location", code: response.code.to_i, reason_code: "redirect_error") if location.nil? || redirects_left.zero?

      probe(location, redirects_left - 1, method: :head)
    when Net::HTTPSuccess
      landed_outcome(code: response.code.to_i, final_url: uri.to_s)
    else
      code = response.code.to_i
      # Some servers reject HEAD (405/501) — retry once with GET before judging.
      return probe(uri, redirects_left, method: :get) if method == :head && [405, 501].include?(code)
      return inconclusive_outcome("server responded #{code} (access-restricted)", code: code, final_url: uri.to_s, reason_code: "bot_blocked") if BOT_BLOCK_CODES.include?(code)
      # 5xx (incl. Cloudflare origin errors 520-530) means the edge is reachable but the
      # origin is erroring — frequently transient. Inconclusive, not broken, to avoid
      # penalizing a live-but-hiccuping site.
      return inconclusive_outcome("server responded #{code} (server error)", code: code, final_url: uri.to_s, reason_code: "server_error") if code >= 500

      failure_outcome("HTTP #{code}", code: code, final_url: uri.to_s, reason_code: "http_#{code}")
    end
  rescue OpenSSL::SSL::SSLError => e
    tls_fallback(uri, e)
  rescue StandardError => e
    failure_outcome("#{e.class}: #{e.message}", reason_code: classify_error(e))
  end

  def classify_error(error)
    case error
    when Net::OpenTimeout, Net::ReadTimeout, Timeout::Error then "timeout"
    when SocketError then "dns_failure"
    when Errno::ECONNREFUSED then "connection_refused"
    when Errno::ECONNRESET then "connection_reset"
    when Errno::EHOSTUNREACH, Errno::ENETUNREACH then "host_unreachable"
    when OpenSSL::SSL::SSLError then "ssl_error"
    else "connection_error"
    end
  end

  # A TLS/certificate error means verification failed, but the host is often still
  # live (missing intermediate chain, hostname mismatch, self-signed cert). Retry once
  # with verification disabled: if the server answers at all, the site is reachable, so
  # treat it as inconclusive rather than broken — this prevents flagging live companies
  # (e.g. behind a CDN with a trust-chain quirk) as dead.
  def tls_fallback(uri, error)
    response = request(uri, :head, verify: false)
    inconclusive_outcome("reachable but TLS cert not trusted (HTTP #{response.code})", code: response.code.to_i, final_url: uri.to_s, reason_code: "tls_untrusted")
  rescue StandardError
    failure_outcome("#{error.class}: #{error.message}", reason_code: "ssl_error")
  end

  def request(uri, method, verify: true)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE unless verify
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    http.max_retries = 0

    request_class = method == :head ? Net::HTTP::Head : Net::HTTP::Get
    req = request_class.new(uri.request_uri.presence || "/")
    req["User-Agent"] = USER_AGENT
    req["Accept"] = "*/*"
    http.request(req)
  end

  def redirect_target(current_uri, location)
    return nil if location.blank?

    target = URI.join(current_uri.to_s, location)
    target.is_a?(URI::HTTP) && target.host.present? ? target : nil
  rescue URI::InvalidURIError
    nil
  end

  # A 2xx is only "ok" if it is still the company's site. The verdict used to ignore
  # where the redirects ended, so hijacked domains passed as healthy.
  def landed_outcome(code:, final_url:)
    requested = Company.canonical_domain_for(company.main_url)
    landed = Company.canonical_domain_for(final_url)
    return success_outcome(code: code, final_url: final_url) if same_site?(requested, landed)

    if landed.match?(HIJACK_HOST_PATTERN)
      return { "result" => "hijack", "status_code" => code, "final_url" => final_url, "reason" => "redirects to #{landed}, which looks like a gambling or spam site", "reason_code" => "suspected_hijack" }
    end

    inconclusive_outcome("redirects to a different domain (#{landed})", code: code, final_url: final_url, reason_code: "offsite_redirect")
  end

  # Same site: the same host or a subdomain of it either way, or the same brand label
  # on another TLD (legalsign.ai -> legalsign.com).
  def same_site?(requested, landed)
    return true if requested.blank? || landed.blank? || requested == landed
    return true if landed.end_with?(".#{requested}") || requested.end_with?(".#{landed}")

    brand_label(requested) == brand_label(landed)
  end

  def brand_label(domain)
    domain.split(".").first
  end

  def success_outcome(code:, final_url:)
    { "result" => Company::URL_STATUS_OK, "status_code" => code, "final_url" => final_url, "reason_code" => Company::URL_STATUS_OK }
  end

  def inconclusive_outcome(reason, code: nil, final_url: nil, reason_code: "connection_error")
    { "result" => Company::URL_STATUS_UNKNOWN, "status_code" => code, "final_url" => final_url, "reason" => reason, "reason_code" => reason_code }
  end

  def failure_outcome(reason, code: nil, final_url: nil, reason_code: "connection_error")
    { "result" => "failure", "status_code" => code, "final_url" => final_url, "reason" => reason, "reason_code" => reason_code }
  end

  def record_invalid!
    persist!(inconclusive_outcome("no usable main_url", reason_code: "invalid_url"))
    { "company_id" => company.id, "url_status" => company.url_status, "result" => "invalid_url" }
  end

  # Writes the verdict with update_columns to bypass validations/callbacks (the
  # record may be otherwise-invalid, and we must not trigger geocoding/logo fetches).
  def persist!(outcome)
    failing = outcome["result"] == "failure"
    prior_failures = company.url_health&.dig("consecutive_failures").to_i
    consecutive = failing ? prior_failures + 1 : 0

    url_status = if outcome["result"] == "hijack"
      Company::URL_STATUS_BROKEN
    elsif failing
      consecutive >= FAILURE_THRESHOLD ? Company::URL_STATUS_BROKEN : Company::URL_STATUS_UNKNOWN
    else
      outcome["result"]
    end

    health = {
      "consecutive_failures" => consecutive,
      "final_url" => outcome["final_url"],
      "reason" => outcome["reason"],
      "reason_code" => outcome["reason_code"],
      "checked_at" => Time.current.utc.iso8601
    }
    health["last_ok_at"] = Time.current.utc.iso8601 if url_status == Company::URL_STATUS_OK
    health["last_ok_at"] ||= company.url_health&.dig("last_ok_at")

    company.update_columns(
      url_status: url_status,
      url_status_code: outcome["status_code"],
      url_checked_at: Time.current,
      url_health: health.compact
    )
  end
end
