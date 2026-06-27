require "digest"
require "uri"

class Company < ActiveRecord::Base
  attr_accessor :skip_geocoding

  before_update :publish_tweet, :if => :visible_changed?
  before_update :publish_to_list, :if => :visible_changed?
  before_validation :normalize_status

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
  validates :founded_date, presence: true, format: {with: /\d\d\d\d/, message: "must be a 4-digit year."}
  validates :category, presence: true
  validate :must_have_at_least_one_revenue_model
  validates :target_client, presence: true
  validates :description, presence: true, length: {minimum: 5}

  scope :publicly_visible, -> { where(visible: true) }
  scope :missing_main_url, -> { where(main_url: [nil, ""]) }
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

  #geocoding

  geocoded_by :location
  after_validation :geocode, if: ->(obj) { obj.location.present? && obj.location_changed? && !obj.skip_geocoding }

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

  def self.normalized_name_value(value)
    value.to_s.downcase.gsub(/[^\p{Alnum}]+/, " ").squish
  end

  def self.canonical_domain_for(url)
    raw = url.to_s.strip.downcase
    return nil if raw.blank? || raw == "unknown"

    raw = "http://#{raw}" unless raw.match?(%r{\Ahttps?://})
    URI.parse(raw).host&.sub(/\Awww\./, "")
  rescue URI::InvalidURIError
    nil
  end

  def self.fingerprint_for(name, url)
    normalized_name = normalized_name_value(name)
    canonical_domain = canonical_domain_for(url)
    identity = [normalized_name, canonical_domain].compact_blank.join("|")

    Digest::SHA256.hexdigest(identity) if identity.present?
  end

  def self.duplicate_name_candidate_ids
    duplicate_candidate_cache[:name] ||= begin
      rows = where.not(name: [nil, ""]).pluck(:id, :name)
      grouped = rows.group_by { |_id, name| normalized_name_value(name) }
      grouped.values.select { |group| group.size > 1 }.flatten(1).map(&:first)
    end
  end

  def self.duplicate_domain_candidate_ids
    duplicate_candidate_cache[:domain] ||= begin
      stored_ids = if column_names.include?("canonical_domain")
        duplicate_domains = where.not(canonical_domain: [nil, ""]).group(:canonical_domain).having("COUNT(*) > 1").select(:canonical_domain)
        where(canonical_domain: duplicate_domains).pluck(:id)
      else
        []
      end

      rows = where.not(main_url: [nil, ""]).pluck(:id, :main_url)
      grouped = rows.group_by { |_id, main_url| canonical_domain_for(main_url) }
      fallback_ids = grouped.except(nil).values.select { |group| group.size > 1 }.flatten(1).map(&:first)

      (stored_ids + fallback_ids).uniq
    end
  end

  def self.duplicate_candidate_cache
    store = ActiveSupport::IsolatedExecutionState[:company_duplicate_candidate_ids] ||= {}
    cache_key = [maximum(:updated_at)&.utc&.iso8601(6), count]
    if store[:cache_key] != cache_key
      store.clear
      store[:cache_key] = cache_key
    end
    store
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

  def canonical_main_domain
    self.class.canonical_domain_for(main_url)
  end

  def calculated_fingerprint
    self.class.fingerprint_for(name, main_url)
  end

  def normalize_status
    self.status = status.to_s.strip.downcase.presence
  end

  def must_have_at_least_one_revenue_model
    return if business_models.any? || business_model_id.present?

    errors.add(:base, "must have at least one revenue model")
  end

  def revenue_models_label
    revenue_model_names.to_sentence
  end

  def all_tags=(names)
    self.tags = names.split(",").filter_map do |name|
      TagNormalizationService.find_or_create_canonical(name)
    end
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

  def publish_tweet
    if (self.visible? && Rails.configuration.twitter_publish)
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
    if (self.visible? && Rails.configuration.twitter_publish)
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

  def self.ransackable_attributes(auth_object = nil)
    %w[name location founded_date category business_model target_client
       description main_url twitter_url angellist_url crunchbase_url
       linkedin_url facebook_url legalio_url status visible
       contact_name contact_email codex_presenter codex_presentation_date
       employee_count latitude longitude created_at updated_at
       quality_status verification_verdict quality_score verified_at enriched_at
       quality_reviewed_at human_reviewed_at fingerprint canonical_domain source source_url]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[category sub_category business_model business_models target_client taggings tags company_business_models]
  end

  scope :text_search, ->(query) {
    where("name ILIKE :q OR description ILIKE :q OR location ILIKE :q", q: "%#{query}%")
  }

  def logo
    if company_logo.present?
      Rails.application.routes.url_helpers.company_logo_path(self)
    elsif logo_url.present? && !logo_dev_url?(logo_url)
      logo_url
    else
      "https://placehold.co/64x64?text=#{URI.encode_www_form_component(name[0])}"
    end
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
end
