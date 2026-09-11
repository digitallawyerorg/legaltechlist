require "digest"
require "uri"

class Company < ActiveRecord::Base
  include CompanyQualityReview
  include UrlSlug

  attr_accessor :skip_geocoding

  EARLIEST_PLAUSIBLE_FOUNDING_YEAR = 1970

  # URL-health verdicts recorded by CompanyUrlHealthCheckService. A broken URL is a
  # soft signal that a company may have gone inactive — it is surfaced for curator
  # review and never auto-flips the lifecycle status.
  URL_STATUS_OK = "ok".freeze
  URL_STATUS_BROKEN = "broken".freeze
  URL_STATUS_UNKNOWN = "unknown".freeze
  # Statuses we consider already-resolved: no point re-checking a URL we've already
  # decided is dead/acquired.
  URL_CHECK_SKIP_STATUSES = %w[inactive closed acquired].freeze

  before_update :publish_tweet, :if => :visible_changed?
  before_update :publish_to_list, :if => :visible_changed?
  after_commit :sync_legaltech_atlas_link, on: :update, if: :should_sync_legaltech_atlas_link?
  before_validation :normalize_status
  before_validation :sync_structured_location_fields

  has_many :taggings,  dependent: :destroy
  has_many :tags, through: :taggings
  has_many :company_business_models, dependent: :destroy
  has_many :business_models, through: :company_business_models
  has_many :company_target_clients, dependent: :destroy
  has_many :target_clients, through: :company_target_clients
  has_one :company_logo, dependent: :destroy

  #this should be has_one, but apparently there's a known bug
  belongs_to :category, optional: true
  belongs_to :sub_category, optional: true
  belongs_to :secondary_category, class_name: "Category", optional: true
  belongs_to :successor_company, class_name: "Company", optional: true
  belongs_to :business_model, optional: true
  belongs_to :target_client, optional: true

  # I'm not 100% sure these are required.
  accepts_nested_attributes_for :category
  accepts_nested_attributes_for :sub_category
  accepts_nested_attributes_for :business_model
  accepts_nested_attributes_for :target_client

  # Validation for manual entry of data.
  validates :name, presence: true, length: {minimum: 2}
  validates :location, presence: true, length: {minimum: 1}
  # Founding year is optional: it is genuinely unfindable for many small/international
  # legal-tech companies, so it should not block a directory listing. When present it
  # must contain a 4-digit year; never store an unsourced/fabricated year.
  validates :founded_date, format: {with: /\d\d\d\d/, message: "must be a 4-digit year."}, allow_blank: true
  validates :category, presence: true
  validate :must_have_at_least_one_revenue_model
  validates :target_client, presence: true
  validates :description, presence: true, length: {minimum: 5}
  validates :acquirer_url, format: {with: %r{\Ahttps?://}, message: "must be an http(s) URL."}, allow_blank: true

  scope :publicly_visible, -> { where(visible: true) }
  # URL-health scopes for the maintenance sweep and curator review.
  scope :url_broken, -> { where(url_status: URL_STATUS_BROKEN) }
  # Filter by the machine-readable url_health reason_code (bot_blocked / dns_failure /
  # timeout / http_404 / ...) so "unknown" verdicts can be triaged.
  scope :url_reason, ->(code) { where("url_health ->> 'reason_code' = ?", code.to_s) }
  scope :with_main_url, -> { where.not(main_url: [nil, ""]) }
  # Companies believed active (excludes already-resolved lifecycle states) whose URL
  # has not been checked within the cooldown window. ISO-8601 UTC strings compare
  # correctly, but url_checked_at is a real datetime so a plain time comparison works.
  scope :url_check_due, ->(cooldown = 30.days) {
    with_main_url
      .where("status IS NULL OR LOWER(status) NOT IN (?)", URL_CHECK_SKIP_STATUSES)
      .where("url_checked_at IS NULL OR url_checked_at < ?", cooldown.ago)
  }
  scope :missing_main_url, -> { where(main_url: [nil, ""]) }
  scope :missing_founded_date, -> { where(founded_date: [nil, ""]) }
  # Companies still missing a founded_date that have NOT had a server-side backfill
  # attempt within the cooldown window. Uses the founded_year_provenance.attempted_at
  # marker so blind sweeps stop re-researching known no-source companies every run.
  # ISO-8601 UTC timestamps compare correctly as strings (fixed format), avoiding a cast.
  scope :founded_date_backfill_due, ->(cooldown = 3.days) {
    cutoff = cooldown.ago.utc.iso8601
    missing_founded_date.where(
      "founded_year_provenance IS NULL OR (founded_year_provenance ->> 'attempted_at') IS NULL OR (founded_year_provenance ->> 'attempted_at') < ?",
      cutoff
    )
  }
  scope :weak_description, -> { where("description IS NULL OR LENGTH(TRIM(description)) < 40") }
  scope :description_review_candidates, -> { where(description_review_candidate_condition) }
  scope :needs_review, -> { where(quality_status: "needs_review") }
  scope :verified_quality, -> { where(quality_status: "verified") }
  scope :rejected_quality, -> { where(quality_status: "rejected") }
  scope :human_reviewed, -> { where.not(human_reviewed_at: nil) }
  scope :unknown_category, -> { left_joins(:category).where(categories: { name: "Unknown" }) }
  scope :unknown_business_model, -> { left_joins(:company_business_models).where(company_business_models: { id: nil }).where(business_model_id: nil) }
  scope :unknown_target_client, -> { left_joins(:target_client).where(target_clients: { name: "Unknown" }) }
  scope :duplicate_name_candidates, -> { where(id: duplicate_name_candidate_ids) }
  scope :duplicate_domain_candidates, -> { where(id: duplicate_domain_candidate_ids) }
  # Rows the duplicate detector should compare. Curator-resolved duplicates are hidden
  # (visible:false) or rejected-quality; excluding them means hiding/rejecting the loser of
  # a pair drops it from the dup queue instead of re-surfacing forever. IS DISTINCT FROM
  # keeps NULL quality_status rows (they are not "rejected").
  # Visible only, deliberately: hiding the loser is how a company pair gets resolved, so
  # a hidden row is a resolved one here. Intake and duplicate_check use a wider scope,
  # because there an unpublished draft is an unresolved collision, not a resolution.
  scope :dedup_candidates, -> { where(visible: true).where("companies.quality_status IS DISTINCT FROM ?", "rejected") }
  scope :with_normalized_name, ->(normalized_name) {
    return none if normalized_name.blank?

    where.not(name: [nil, ""]).where(
      "TRIM(REGEXP_REPLACE(LOWER(name), '[^[:alnum:]]+', ' ', 'g')) = ?",
      normalized_name
    )
  }
  scope :with_resolved_country, -> { where.not(country: [nil, ""]) }
  scope :with_location_data, -> { where.not(location: [nil, ""]).or(with_resolved_country) }

  #geocoding

  geocoded_by :location
  after_validation :geocode, if: ->(obj) { obj.location.present? && obj.location_changed? && !obj.skip_geocoding }
  after_commit :schedule_logo_fetch_if_needed, on: [:create, :update]

  include PgSearch::Model
  pg_search_scope :search,
                  against: :name,
                  using: {
                    tsearch: { prefix: true }
                  }

  def self.text_search(query)
    if query.present?
      search(query)
    else
      all
    end
  end

  def self.tagged_with(name)
    Tag.find_by!(name: name).companies
  end

  def self.related_to(company, limit: 9)
    tag_ids = company.tag_ids
    category_id = company.category_id
    secondary_category_id = company.secondary_category_id

    return [] if category_id.blank? && secondary_category_id.blank? && tag_ids.empty?

    relevance_conditions = []
    relevance_binds = {}

    if category_id.present?
      relevance_conditions << "companies.category_id = :category_id"
      relevance_binds[:category_id] = category_id
    end

    if secondary_category_id.present?
      relevance_conditions << "companies.secondary_category_id = :secondary_category_id"
      relevance_binds[:secondary_category_id] = secondary_category_id
    end

    if tag_ids.any?
      relevance_conditions << "companies.id IN (SELECT company_id FROM taggings WHERE tag_id IN (:tag_ids))"
      relevance_binds[:tag_ids] = tag_ids
    end

    primary_score = if category_id.present?
                      sanitize_sql_array(["CASE WHEN companies.category_id = ? THEN 1 ELSE 0 END", category_id])
                    else
                      "0"
                    end
    secondary_score = if secondary_category_id.present?
                        sanitize_sql_array(["CASE WHEN companies.secondary_category_id = ? THEN 1 ELSE 0 END", secondary_category_id])
                      else
                        "0"
                      end

    scope = publicly_visible
              .where.not(id: company.id)
              .where(relevance_conditions.join(" OR "), **relevance_binds)

    scope = if tag_ids.any?
              scope
                .left_joins(:taggings)
                .select("companies.*, #{primary_score} AS primary_category_match, #{secondary_score} AS secondary_category_match, COUNT(CASE WHEN taggings.tag_id IN (#{tag_ids.map { |id| connection.quote(id) }.join(',')}) THEN 1 END) AS shared_tags_count")
                .group("companies.id")
            else
              scope
                .select("companies.*, #{primary_score} AS primary_category_match, #{secondary_score} AS secondary_category_match, 0 AS shared_tags_count")
            end

    scope
      .order(Arel.sql("primary_category_match DESC"), Arel.sql("secondary_category_match DESC"), Arel.sql("shared_tags_count DESC"), "companies.name ASC")
      .limit(limit)
      .preload(:category, :secondary_category, :company_logo)
      .to_a
  end

  def self.normalized_name_value(value)
    fold_diacritics(value).downcase.gsub(/[^\p{Alnum}]+/, " ").squish
  end

  # ş → s, ü → u, ö → o. A duplicate that differs only in accents was previously
  # undetectable: searching "Bilisim" returned nothing while "Bilişim" returned the row.
  # I18n.transliterate handles the whole class, including letters like ı and ø that
  # decomposition alone does not touch.
  def self.fold_diacritics(value)
    text = value.to_s.dup.force_encoding(Encoding::UTF_8)
    text = text.scrub("") unless text.valid_encoding?
    I18n.transliterate(text, replacement: "")
  rescue StandardError
    value.to_s
  end

  def self.canonical_domain_for(url)
    raw = url.to_s.strip.downcase
    return nil if raw.blank? || raw == "unknown"

    raw = "http://#{raw}" unless raw.match?(%r{\Ahttps?://})
    URI.parse(raw).host&.sub(/\Awww\./, "")
  rescue URI::InvalidURIError
    nil
  end

  def self.valid_http_url?(value)
    uri = URI.parse(value.to_s.strip)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  # Cite-only writer for founded_date shared by the curator tool and the backfill
  # service: a founding year is only stored with a valid 4-digit year AND a source URL.
  def founded_date_from_source!(year:, source_url:)
    raise ArgumentError, "founded_date must be a 4-digit year #{EARLIEST_PLAUSIBLE_FOUNDING_YEAR}-#{Date.current.year}" unless plausible_founding_year?(year)
    raise ArgumentError, "source_url required (cite-only)" unless self.class.valid_http_url?(source_url)

    self.founded_date = year.to_s.strip
    self.quality_review = (quality_review.is_a?(Hash) ? quality_review : {}).merge(
      "founded_date_source" => { "year" => year.to_s.strip, "source_url" => source_url, "recorded_at" => Time.current.utc.iso8601 }
    )
    save!
  end

  def plausible_founding_year?(value)
    value.to_s.strip.match?(/\A(?:19|20)\d{2}\z/) &&
      (EARLIEST_PLAUSIBLE_FOUNDING_YEAR..Date.current.year).cover?(value.to_s.strip.to_i)
  end

  def self.fingerprint_for(name, url)
    normalized_name = normalized_name_value(name)
    canonical_domain = canonical_domain_for(url)
    identity = [normalized_name, canonical_domain].compact_blank.join("|")

    Digest::SHA256.hexdigest(identity) if identity.present?
  end

  def self.duplicate_name_candidate_ids
    duplicate_candidate_cache[:name] ||= Rails.cache.fetch("companies/duplicate_name_candidate_ids/#{duplicate_candidate_cache_version}", expires_in: 10.minutes) do
      compute_duplicate_name_candidate_ids
    end
  end

  def self.duplicate_domain_candidate_ids
    duplicate_candidate_cache[:domain] ||= Rails.cache.fetch("companies/duplicate_domain_candidate_ids/#{duplicate_candidate_cache_version}", expires_in: 10.minutes) do
      compute_duplicate_domain_candidate_ids
    end
  end

  def self.duplicate_candidate_cache_version
    Rails.cache.fetch("companies/duplicate_candidate_cache_version", expires_in: 10.minutes) do
      "#{maximum(:updated_at)&.utc&.iso8601(6)}-#{count}"
    end
  end

  def self.duplicate_candidate_cache
    store = ActiveSupport::IsolatedExecutionState[:company_duplicate_candidate_ids] ||= {}
    cache_key = duplicate_candidate_cache_version
    if store[:cache_key] != cache_key
      store.clear
      store[:cache_key] = cache_key
    end
    store
  end

  def self.compute_duplicate_name_candidate_ids
    rows = dedup_candidates.where.not(name: [nil, ""]).pluck(:id, :name)
    grouped = rows.group_by { |_id, name| normalized_name_value(name) }
    grouped.values.select { |group| group.size > 1 }.flatten(1).map(&:first)
  end

  # Duplicate candidate groups (for list_duplicate_candidates): each entry is
  # { "value" => matched_value, "ids" => [company_id, ...] } for a normalized name /
  # canonical domain shared by more than one company.
  # Companies whose names reduce to the same identity core once corporate-form and
  # product suffixes are ignored, regardless of domain. "Deep Law" on deep-law.com and
  # deep-law.io share no domain and were never compared.
  def self.duplicate_core_name_groups
    rows = dedup_candidates.where.not(name: [nil, ""]).pluck(:id, :name)
    rows.group_by { |_id, name| ProposalDuplicateDetectorService.core_name(name) }
        .select { |core, group| core.present? && group.size > 1 }
        .map { |core, group| { "value" => core, "ids" => group.map(&:first).sort } }
  end

  def self.duplicate_name_groups
    rows = dedup_candidates.where.not(name: [nil, ""]).pluck(:id, :name)
    rows.group_by { |_id, name| normalized_name_value(name) }
        .select { |value, group| value.present? && group.size > 1 }
        .map { |value, group| { "value" => value, "ids" => group.map(&:first).sort } }
  end

  def self.duplicate_domain_groups
    has_canonical = column_names.include?("canonical_domain")
    cols = has_canonical ? [:id, :main_url, :canonical_domain] : [:id, :main_url]
    scope = dedup_candidates.where.not(main_url: [nil, ""])
    scope = scope.or(dedup_candidates.where.not(canonical_domain: [nil, ""])) if has_canonical
    rows = scope.pluck(*cols)

    rows.group_by { |row| (has_canonical ? row[2].presence : nil) || canonical_domain_for(row[1]) }
        .select { |domain, group| domain.present? && group.size > 1 }
        .map { |domain, group| { "value" => domain, "ids" => group.map(&:first).sort } }
  end

  # Ids within `scope` whose resolved+normalized country matches `name`. Country is
  # free text (with native-language variants), so matching is done in Ruby via the
  # LocationCountryResolver canonicalization used across the statistics pages.
  def self.ids_with_normalized_country(name, scope: all)
    target = LocationCountryResolver.normalize_country_name(name)
    return [] if target.blank?

    scope.pluck(:id, :country, :location).filter_map do |id, country, location|
      resolved = country.presence || LocationCountryResolver.country_name_for(location)
      next if resolved.blank?

      id if LocationCountryResolver.normalize_country_name(resolved) == target
    end
  end

  def self.compute_duplicate_domain_candidate_ids
    stored_ids = if column_names.include?("canonical_domain")
      duplicate_domains = dedup_candidates.where.not(canonical_domain: [nil, ""]).group(:canonical_domain).having("COUNT(*) > 1").select(:canonical_domain)
      dedup_candidates.where(canonical_domain: duplicate_domains).pluck(:id)
    else
      []
    end

    rows = dedup_candidates.where.not(main_url: [nil, ""]).pluck(:id, :main_url)
    grouped = rows.group_by { |_id, main_url| canonical_domain_for(main_url) }
    fallback_ids = grouped.except(nil).values.select { |group| group.size > 1 }.flatten(1).map(&:first)

    (stored_ids + fallback_ids).uniq
  end

  def self.description_review_candidate_condition
    <<~SQL.squish
      description IS NULL
      OR LENGTH(TRIM(description)) < 80
      OR description ILIKE '%leading%'
      OR description ILIKE '%best%'
      OR description ILIKE '%revolutionary%'
      OR description ILIKE '%cutting-edge%'
      OR description ILIKE '%world-class%'
      OR description ILIKE '%game-changing%'
      OR description ILIKE '%listed in TechIndex%'
      OR description ILIKE '%included in TechIndex%'
      OR description ILIKE '%directory metadata%'
      OR description ILIKE '%based on available%'
    SQL
  end

  def normalized_name
    self.class.normalized_name_value(name)
  end

  def self.duplicates_by_normalized_name_for(company)
    with_normalized_name(company.normalized_name).where.not(id: company.id).order(:name)
  end

  # Cross-domain duplicates for a single record. Deliberately not restricted to visible
  # rows the way the pair queue's scan is: on the pair queue hiding the loser is how a
  # pair gets resolved, but on a record page the question is "does another entry for
  # this company already exist anywhere", and an unpublished draft is precisely the row
  # that would otherwise be minted a second time.
  def self.duplicates_by_core_name_for(company)
    core = ProposalDuplicateDetectorService.core_name(company.name)
    return none if core.blank?

    ids = where.not(name: [nil, ""]).where.not(id: company.id).pluck(:id, :name)
               .select { |_id, name| ProposalDuplicateDetectorService.core_name(name) == core }
               .map(&:first)
    return none if ids.empty?

    where(id: ids).order(:name)
  end

  def self.duplicates_by_domain_for(company)
    domain = company.canonical_domain.presence || company.canonical_main_domain
    return none if domain.blank?

    stored_matches = where(canonical_domain: domain).where.not(id: company.id)
    return stored_matches.order(:name) if company.canonical_domain.present?

    return none unless duplicate_domain_candidate_ids.include?(company.id)

    where(id: duplicate_domain_candidate_ids).where.not(id: company.id).order(:name).select { |match| (match.canonical_domain.presence || match.canonical_main_domain) == domain }
  end

  def canonical_main_domain
    self.class.canonical_domain_for(main_url)
  end

  def calculated_fingerprint
    self.class.fingerprint_for(name, main_url)
  end

  def normalize_status
    self.status = status.to_s.strip.downcase.presence
  end

  def url_broken?
    url_status == URL_STATUS_BROKEN
  end

  def url_consecutive_failures
    url_health&.dig("consecutive_failures").to_i
  end

  # Acquisition display data, preferring an in-DB successor link (canonical) and
  # falling back to the free-text acquirer captured when the acquirer is not in the
  # index (e.g. a non-legal-tech buyer). Returns nil when nothing is recorded.
  def acquirer_display
    if successor_company.present?
      { name: successor_company.name, url: nil, company: successor_company }
    elsif acquirer_name.present?
      { name: acquirer_name, url: acquirer_url.presence, company: nil }
    end
  end

  def acquired?
    status.to_s.downcase == "acquired"
  end

  def sync_structured_location_fields
    if will_save_change_to_country? || will_save_change_to_city?
      composed = compose_location(city, country)
      self.location = composed if composed.present?
    elsif will_save_change_to_location?
      parsed = LocationCountryResolver.parse(location)
      self.country = parsed[:country] if parsed[:country].present?
      self.city = parsed[:city]
    end
  end

  def compose_location(city_value, country_value)
    # city and country have no slot for a sub-national region, so recomposing from them
    # silently deleted one: "Wiesbaden, Hesse, Germany" came back as "Wiesbaden,
    # Germany". When the stored location already says more than the two parts do, and
    # still agrees with them, it is the better value and is kept.
    detailed = detailed_location_matching(city_value, country_value)
    return detailed if detailed

    if city_value.present? && country_value.present?
      "#{city_value}, #{country_value}"
    elsif country_value.present?
      country_value
    elsif city_value.present?
      city_value
    end
  end

  def detailed_location_matching(city_value, country_value)
    current = location.to_s.strip
    return nil if current.blank? || city_value.blank? || country_value.blank?

    parts = current.split(",").map(&:strip).reject(&:blank?)
    return nil unless parts.size > 2
    return nil unless parts.first.casecmp?(city_value.to_s.strip) && parts.last.casecmp?(country_value.to_s.strip)

    current
  end

  def resolved_country
    country.presence || LocationCountryResolver.country_name_for(location)
  end

  def display_location
    composed = compose_location(city, country)
    composed.presence || location
  end

  def must_have_at_least_one_revenue_model
    return if business_models.any? || business_model_id.present?

    errors.add(:base, "must have at least one revenue model")
  end

  def revenue_models_label
    revenue_model_names.to_sentence
  end

  # Rejected names are reported rather than silently created or folded elsewhere.
  attr_reader :rejected_tag_names

  def all_tags=(names)
    @rejected_tag_names = []
    resolved = names.to_s.split(",").filter_map do |name|
      tag = TagNormalizationService.find_existing_canonical(name)
      @rejected_tag_names << name.strip if tag.nil? && name.strip.present?
      tag
    end
    self.tags = resolved.uniq
  end

  def all_tags
    self.tags.map(&:name).join(", ")
  end

  def revenue_model_names
    revenue_models.map(&:name)
  end

  def revenue_models
    business_models.presence || Array(business_model).compact
  end

  def audience_names
    names = target_clients.map(&:name).presence
    names ||= TaxonomyNormalizationService.canonical_target_client_names(target_client&.name)
    names.uniq
  end

  def target_client_ids=(ids)
    ids = Array(ids).map(&:presence).compact.map(&:to_i).uniq
    self.target_clients = TargetClient.where(id: ids)
    self.target_client_id = ids.first
  end

  def business_model_ids=(ids)
    ids = Array(ids).map(&:presence).compact.map(&:to_i).uniq
    self.business_models = BusinessModel.where(id: ids)
    self.business_model_id = ids.first
  end

  def revenue_model_names=(names)
    names = names.is_a?(String) ? names.split(",") : Array(names)
    records = names.filter_map do |name|
      normalized = name.to_s.strip
      next if normalized.blank?

      BusinessModel.find_by(name: normalized) || BusinessModel.find_by("LOWER(name) = ?", normalized.downcase)
    end.uniq
    self.business_models = records
    self.business_model_id = records.first&.id
  end

  #convenience method to parse the twitter username from the twitter url,
  #but also handle the case where the user entered their twitter name instead.
  def twitter_name
    #parse the twitter url to get the twitter_name
    if self.twitter_url.present?
      if self.twitter_url.include? "twitter.com/"
        if self.twitter_url.split('twitter.com/').last.include? "@"
          self.twitter_url.split('twitter.com/').last.split('@').last
        else
          self.twitter_url.split('twitter.com/').last
        end
      else
        if self.twitter_url.include? "@"
          self.twitter_url.split('@').last
        else
          self.twitter_url
        end
      end
    else
      nil
    end
  end

  def twitter_publish_enabled?
    Rails.configuration.respond_to?(:twitter_publish) && Rails.configuration.twitter_publish
  end

  def publish_tweet
    if (self.visible? && twitter_publish_enabled?)
      #initialize twitter_client to access their API
      twitter_client = Twitter::REST::Client.new do |config|
          config.consumer_key        = ENV["TWITTER_CONSUMER_KEY"]
          config.consumer_secret     = ENV["TWITTER_CONSUMER_SECRET"]
          config.access_token        = ENV["TWITTER_ACCESS_TOKEN"]
          config.access_token_secret = ENV["TWITTER_ACCESS_SECRET"]
      end

      #publish a tweet
      if self.twitter_name.nil?
        #then don't include it
        twitter_client.update(I18n.t("twitter.publish") + " " + self.main_url)
      else
        #include twittername
        twitter_client.update(I18n.t("twitter.publish") + " @" + self.twitter_name + " " + self.main_url)
      end
    end
  end

  def publish_to_list
    if (self.visible? && twitter_publish_enabled?)
      #initialize twitter_client to access their API
      twitter_client = Twitter::REST::Client.new do |config|
          config.consumer_key        = ENV["TWITTER_CONSUMER_KEY"]
          config.consumer_secret     = ENV["TWITTER_CONSUMER_SECRET"]
          config.access_token        = ENV["TWITTER_ACCESS_TOKEN"]
          config.access_token_secret = ENV["TWITTER_ACCESS_SECRET"]
      end

      #add users to the list
      if (self.twitter_name.present?)
        begin
          twitter_client.add_list_member(Rails.configuration.twitter_user,Rails.configuration.twitter_list, self.twitter_name)
        rescue Twitter::Error::Forbidden
          logger.error "#{self.twitter_name} is not a valid twitter id"
        end
      end
    end
  end

  def should_sync_legaltech_atlas_link?
    saved_change_to_visible? && visible? && legaltech_atlas_url.blank?
  end

  def sync_legaltech_atlas_link
    LegaltechAtlasLinkSyncJob.perform_later(id)
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[name location country city founded_date category business_model target_client
       description main_url twitter_url angellist_url crunchbase_url
       linkedin_url facebook_url legalio_url status visible
       contact_name contact_email codex_presenter codex_presentation_date
       latitude longitude created_at updated_at
       quality_status verification_verdict quality_score verified_at enriched_at
       quality_reviewed_at human_reviewed_at fingerprint canonical_domain source source_url
       legaltech_atlas_url acquirer_name acquirer_url url_status url_status_code url_checked_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[category sub_category business_model business_models target_client taggings tags company_business_models]
  end

  scope :text_search, ->(query) {
    where(
      "companies.name ILIKE :q OR companies.description ILIKE :q OR companies.location ILIKE :q OR companies.city ILIKE :q OR companies.country ILIKE :q",
      q: "%#{query}%"
    )
  }

  def logo
    if company_logo.present?
      Rails.application.routes.url_helpers.company_logo_path(id)
    elsif logo_url.present? && !logo_dev_url?(logo_url)
      logo_url
    else
      "https://placehold.co/64x64?text=#{URI.encode_www_form_component(name[0])}"
    end
  end

  def logo_placeholder?
    company_logo.blank? && (logo_url.blank? || logo_dev_url?(logo_url))
  end

  def self.logo_dev_url?(url)
    return false if url.blank?

    host = URI.parse(url).host
    host&.include?("logo.dev")
  rescue URI::InvalidURIError
    false
  end

  def logo_dev_url?(url)
    self.class.logo_dev_url?(url)
  end

  def logo_fetch_needed?
    return false unless visible?
    return false if company_logo.present?
    return false if main_url.blank?
    return false unless canonical_main_domain
    return false if logo_url.present? && !logo_dev_url?(logo_url)

    true
  end

  private

  def schedule_logo_fetch_if_needed
    return unless logo_fetch_needed?
    return unless previously_new_record? || saved_change_to_visible? || saved_change_to_main_url?

    LogoFetcherService.schedule_fetch_for(self)
  end
end
