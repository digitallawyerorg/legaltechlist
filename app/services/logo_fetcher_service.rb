require "cgi"
require "net/http"
require "uri"

class LogoFetcherService
  Result = Struct.new(:checked, :updated, :skipped_existing, :skipped_no_domain, :skipped_unverified, :errors, :examples, keyword_init: true)

  DEFAULT_LIMIT = 100
  DEFAULT_SIZE = 128
  VERIFY_TIMEOUT_SECONDS = 8
  PLACEHOLDER_HOSTS = ["placehold.co"].freeze

  def self.backfill_missing_logos(scope: Company.publicly_visible, dry_run: true, limit: DEFAULT_LIMIT, provider: nil, logger: $stdout, verifier: nil)
    new(scope: scope, dry_run: dry_run, limit: limit, provider: provider, logger: logger, verifier: verifier).backfill_missing_logos
  end

  def initialize(scope:, dry_run:, limit:, provider:, logger:, verifier:)
    @scope = scope
    @dry_run = dry_run
    @limit = limit
    @provider = provider&.to_sym
    @logger = logger
    @verifier = verifier || method(:verified_image_url?)
  end

  def backfill_missing_logos
    result = Result.new(checked: 0, updated: 0, skipped_existing: 0, skipped_no_domain: 0, skipped_unverified: 0, errors: 0, examples: [])

    companies_to_check.find_each do |company|
      result.checked += 1

      begin
        unless replaceable_logo?(company.logo_url)
          result.skipped_existing += 1
          next
        end

        domain = Company.canonical_domain_for(company.main_url)
        unless domain
          result.skipped_no_domain += 1
          next
        end

        logo_url = verified_candidate_for(domain)
        unless logo_url
          result.skipped_unverified += 1
          next
        end

        company.update!(logo_url: logo_url) unless @dry_run
        result.updated += 1
        result.examples << { id: company.id, name: company.name, domain: domain, logo_url: logo_url } if result.examples.size < 10
        log("#{mode_label} #{company.id} #{company.name} -> #{logo_url}")
      rescue => e
        result.errors += 1
        Rails.logger.debug("Logo backfill error for company #{company.id}: #{e.class} #{e.message}") if defined?(Rails)
        log("ERROR #{company.id} #{company.name}: #{e.class} #{e.message}")
      end
    end

    result
  end

  private

  attr_reader :provider

  def companies_to_check
    relation = @scope.order(:id)
    @limit.present? ? relation.limit(@limit.to_i) : relation
  end

  def replaceable_logo?(logo_url)
    return true if logo_url.blank?

    host = URI.parse(logo_url).host
    PLACEHOLDER_HOSTS.include?(host)
  rescue URI::InvalidURIError
    true
  end

  def verified_candidate_for(domain)
    candidate_urls(domain).find { |url| @verifier.call(url) }
  end

  def candidate_urls(domain)
    case provider
    when :logo_dev
      logo_dev_candidate(domain) ? [logo_dev_candidate(domain)] : []
    when :duckduckgo
      [duckduckgo_candidate(domain)]
    else
      [logo_dev_candidate(domain), duckduckgo_candidate(domain)].compact
    end
  end

  def logo_dev_candidate(domain)
    token = ENV["LOGO_DEV_PUBLISHABLE_KEY"].presence
    return nil unless token

    "https://img.logo.dev/#{CGI.escape(domain)}?token=#{CGI.escape(token)}&size=#{DEFAULT_SIZE}&format=png&fallback=404"
  end

  def duckduckgo_candidate(domain)
    "https://icons.duckduckgo.com/ip3/#{CGI.escape(domain)}.ico"
  end

  def verified_image_url?(url)
    uri = URI.parse(url)
    response = request(uri, Net::HTTP::Head)
    response = request(uri, Net::HTTP::Get) if response.is_a?(Net::HTTPMethodNotAllowed)

    response.is_a?(Net::HTTPSuccess) && response["content-type"].to_s.start_with?("image/")
  rescue URI::InvalidURIError, SocketError, Timeout::Error, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout
    false
  end

  def request(uri, request_class)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: VERIFY_TIMEOUT_SECONDS, read_timeout: VERIFY_TIMEOUT_SECONDS) do |http|
      request = request_class.new(uri)
      http.request(request)
    end
  end

  def mode_label
    @dry_run ? "DRY RUN" : "UPDATED"
  end

  def log(message)
    @logger.puts(message) if @logger
  end
end
