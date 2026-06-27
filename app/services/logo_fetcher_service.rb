require "cgi"
require "net/http"
require "uri"

class LogoFetcherService
  MissingConfiguration = Class.new(StandardError)
  Result = Struct.new(:checked, :updated, :skipped_existing, :skipped_no_domain, :skipped_unverified, :errors, :examples, keyword_init: true)

  DEFAULT_LIMIT = 100
  DEFAULT_SIZE = 128
  VERIFY_TIMEOUT_SECONDS = 8
  REPLACEABLE_LOGO_HOSTS = ["placehold.co", "icons.duckduckgo.com"].freeze

  def self.backfill_missing_logos(scope: Company.publicly_visible, dry_run: true, limit: DEFAULT_LIMIT, provider: :logo_dev, logger: $stdout, verifier: nil)
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
    validate_configuration!

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

  def validate_configuration!
    case provider
    when :logo_dev
      logo_dev_token
    else
      raise ArgumentError, "Unsupported logo provider: #{provider}"
    end
  end

  def companies_to_check
    relation = replaceable_logo_scope(@scope)
    @limit.present? ? relation.limit(@limit.to_i) : relation
  end

  def replaceable_logo_scope(scope)
    scope.where("logo_url IS NULL OR logo_url = ? OR logo_url LIKE ? OR logo_url LIKE ? OR logo_url LIKE ?", "", "%placehold.co%", "%placeholder%", "%icons.duckduckgo.com%")
  end

  def replaceable_logo?(logo_url)
    return true if logo_url.blank?

    host = URI.parse(logo_url).host
    REPLACEABLE_LOGO_HOSTS.include?(host)
  rescue URI::InvalidURIError
    true
  end

  def verified_candidate_for(domain)
    candidate_urls(domain).find { |url| @verifier.call(url) }
  end

  def candidate_urls(domain)
    case provider
    when :logo_dev
      [logo_dev_candidate(domain)]
    else
      raise ArgumentError, "Unsupported logo provider: #{provider}"
    end
  end

  def logo_dev_candidate(domain)
    token = logo_dev_token

    "https://img.logo.dev/#{CGI.escape(domain)}?token=#{CGI.escape(token)}&size=#{DEFAULT_SIZE}&format=png&fallback=404"
  end

  def logo_dev_token
    token = ENV["LOGO_DEV_API_KEY"].presence || ENV["LOGO_DEV_PUBLISHABLE_KEY"].presence
    raise MissingConfiguration, "Set LOGO_DEV_API_KEY to a logo.dev publishable image key before backfilling logos" unless token
    raise MissingConfiguration, "LOGO_DEV_API_KEY must be a publishable logo.dev image key, not a secret sk_ key" if token.start_with?("sk_")

    token
  end

  def verified_image_url?(url)
    uri = URI.parse(url)
    response = request(uri, Net::HTTP::Head)
    response = request(uri, Net::HTTP::Get) unless response.is_a?(Net::HTTPSuccess)

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
