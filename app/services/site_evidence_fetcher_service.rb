require "net/http"
require "uri"
require "nokogiri"

# Retrieves the company's own pages so enrichment has first-party evidence to work
# from, instead of only a search summary and the submitter's self-reported links.
#
# Before this existed, the review packets said so themselves: "Current evidence is
# limited to stored URLs and company-record summary material; webpage content has not
# been checked." Enrichment then wrote capability claims that nothing in the packet
# supported, and the reviewer had no way to tell a researched record from an
# unresearched one.
#
# Every attempt is recorded with an explicit outcome, because "we could not retrieve
# this" and "we never tried" are different facts and only the first is a finding:
#
#   fetched   HTML retrieved and text extracted
#   blocked   server is up but refused automated access (WAF, or a sign-in wall —
#             LinkedIn answers this way for almost every server-side request)
#   error     unreachable, timed out, or returned an error status
#   skipped   no usable URL of this kind on the record
class SiteEvidenceFetcherService
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 8
  MAX_REDIRECTS = 4
  MAX_BYTES = 400_000
  # Enough page text for a description and capability claims to be grounded in it,
  # without bloating agent_details or the enrichment prompt.
  MAX_TEXT_PER_PAGE = 4_000
  USER_AGENT = "CodeX-TechIndex-Research/1.0 (+https://techindex.law.stanford.edu)".freeze

  # Up but refusing robots. Not evidence of a dead site, and not our finding to fix.
  BLOCK_CODES = [401, 403, 405, 406, 429, 451, 999].freeze

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def self.enabled?
    ENV.fetch("PROPOSAL_SITE_FETCH", Rails.env.test? ? "false" : "true") == "true"
  end

  def initialize(main_url: nil, linkedin_url: nil, crunchbase_url: nil)
    @main_url = main_url.to_s.strip.presence
    @linkedin_url = linkedin_url.to_s.strip.presence
    @crunchbase_url = crunchbase_url.to_s.strip.presence
  end

  def call
    return disabled_payload unless self.class.enabled?

    {
      "mode" => "http_fetch",
      "pages" => targets.map { |label, url, guessed| page_for(label, url, guessed: guessed) },
      "generated_at" => Time.current.utc.iso8601
    }
  end

  # Text blocks suitable for pasting into an enrichment prompt, each labelled with the
  # URL it came from so the model can attribute what it uses.
  def self.evidence_text(payload)
    Array(payload && payload["pages"]).select { |page| page["status"] == "fetched" }.map do |page|
      "SOURCE #{page['final_url'].presence || page['url']}\n#{page['title'].presence}\n#{page['text']}".strip
    end
  end

  private

  attr_reader :main_url, :linkedin_url, :crunchbase_url

  # Bounded on purpose: the company's front page carries the product claims, /about
  # carries the founding and location facts, and the profile pages carry the
  # third-party corroboration. Three or four requests, not a crawl.
  # Pages that establish who the company is, as distinct from what the product does.
  # A footer, imprint, terms or privacy page names the legal entity when the product
  # branding does not — which is the whole difficulty in telling Aidvocates Inc. apart
  # from LEGAION.
  ENTITY_PATHS = %w[/about /terms /privacy /legal /imprint].freeze

  def targets
    list = []
    list << ["website", main_url, false] if main_url
    # Guessed rather than declared: plenty of sites have no /about, and its absence is
    # not a retrieval failure worth reporting to a reviewer.
    ENTITY_PATHS.each do |path|
      url = path_url(path)
      list << ["website#{path.tr('/', '_')}", url, true] if url
    end
    list << ["linkedin", linkedin_url, false] if linkedin_url
    list << ["crunchbase", crunchbase_url, false] if crunchbase_url
    list
  end

  def path_url(path)
    return nil if main_url.blank?

    uri = URI.parse(normalize(main_url))
    uri.path = path
    uri.query = nil
    uri.to_s
  rescue StandardError
    nil
  end

  def page_for(label, url, guessed: false)
    outcome = fetch(url)
    # A URL we invented that simply does not exist is an absence, not a failure.
    if guessed && outcome["status"] == "error" && outcome["reason"].to_s.start_with?("http_4")
      outcome = { "status" => "skipped", "reason" => "no_such_page", "http_status" => outcome["http_status"] }
    end
    { "label" => label, "url" => url }.merge(outcome)
  rescue StandardError => e
    { "label" => label, "url" => url, "status" => "error", "reason" => e.class.name.demodulize.underscore }
  end

  # Overridden in tests. Returns the outcome hash for a single URL.
  def fetch(url, redirects_left: MAX_REDIRECTS)
    uri = URI.parse(normalize(url))
    return { "status" => "error", "reason" => "invalid_url" } unless uri.is_a?(URI::HTTP) && uri.host.present?

    response = perform_request(uri)
    code = response.code.to_i

    if response.is_a?(Net::HTTPRedirection)
      location = response["location"]
      return { "status" => "error", "reason" => "redirect_without_location" } if location.blank?
      return { "status" => "error", "reason" => "too_many_redirects" } if redirects_left <= 0

      return fetch(URI.join(uri, location).to_s, redirects_left: redirects_left - 1)
    end

    return { "status" => "blocked", "reason" => block_reason(uri, code), "http_status" => code, "final_url" => uri.to_s } if BLOCK_CODES.include?(code)
    return { "status" => "error", "reason" => "http_#{code}", "http_status" => code, "final_url" => uri.to_s } unless code.between?(200, 299)

    extracted = extract(response.body.to_s.byteslice(0, MAX_BYTES).to_s)
    return { "status" => "error", "reason" => "empty_body", "http_status" => code, "final_url" => uri.to_s } if extracted[:text].blank?

    {
      "status" => "fetched",
      "http_status" => code,
      "final_url" => uri.to_s,
      "title" => extracted[:title],
      "text" => extracted[:text],
      "fetched_at" => Time.current.utc.iso8601
    }
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
    { "status" => "error", "reason" => "timeout" }
  rescue SocketError
    { "status" => "error", "reason" => "dns_failure" }
  rescue OpenSSL::SSL::SSLError
    { "status" => "error", "reason" => "ssl_error" }
  rescue StandardError => e
    { "status" => "error", "reason" => e.class.name.demodulize.underscore }
  end

  def perform_request(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    request = Net::HTTP::Get.new(uri, "User-Agent" => USER_AGENT, "Accept" => "text/html,application/xhtml+xml")
    http.request(request)
  end

  def block_reason(uri, code)
    return "linkedin_requires_sign_in" if uri.host.to_s.include?("linkedin.com")

    "bot_blocked_#{code}"
  end

  def extract(body)
    doc = Nokogiri::HTML(body)
    # The footer stays: it is where the legal entity gets named ("© 2026 Foo
    # Holdings Ltd") when the product branding does not, which is exactly the
    # evidence DescriptionVerificationAgent needs to resolve identity.
    doc.search("script, style, noscript, svg, nav, header, form").remove
    title = doc.at("title")&.text.to_s.squish.presence
    meta = doc.at("meta[name='description']")&.attr("content").to_s.squish
    text = [meta, doc.at("body")&.text.to_s].compact_blank.join(" ").gsub(/\s+/, " ").strip
    { title: title, text: text.truncate(MAX_TEXT_PER_PAGE) }
  rescue StandardError
    { title: nil, text: nil }
  end

  def normalize(url)
    raw = url.to_s.strip
    raw.match?(%r{\Ahttps?://}i) ? raw : "https://#{raw}"
  end

  def disabled_payload
    {
      "mode" => "disabled",
      "pages" => targets.map { |label, url, _guessed| { "label" => label, "url" => url, "status" => "skipped", "reason" => "site_fetch_disabled" } },
      "generated_at" => Time.current.utc.iso8601
    }
  end
end
