require "digest"
require "uri"

class Company < ActiveRecord::Base
  attr_accessor :skip_geocoding

  before_update :publish_tweet, :if => :visible_changed?
  before_update :publish_to_list, :if => :visible_changed?

  has_many :taggings,  dependent: :destroy
  has_many :tags, through: :taggings

  #this should be has_one, but apparently there's a known bug
  belongs_to :category, optional: true
  belongs_to :sub_category, optional: true
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
  validates :business_model, presence: true
  validates :target_client, presence: true
  validates :description, presence: true, length: {minimum: 5}

  scope :publicly_visible, -> { where(visible: true) }

  #geocoding

  geocoded_by :location
  after_validation :geocode, if: ->(obj) { obj.location.present? && obj.location_changed? && !obj.skip_geocoding }

	include PgSearch
	pg_search_scope :search,
                  	:against => :name,
                  	:using => {
                    	:tsearch => {:prefix => true}
                  }

	def self.text_search(query)
		if query.present?
			search(query)
		else
			all
		end
	end

  def self.tagged_with(name)
    Tag.find_by_name!(name).companies
  end

  def self.normalized_name_value(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
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

  def normalized_name
    self.class.normalized_name_value(name)
  end

  def canonical_main_domain
    self.class.canonical_domain_for(main_url)
  end

  def calculated_fingerprint
    self.class.fingerprint_for(name, main_url)
  end

  def all_tags=(names)
    self.tags = names.split(",").map do |name|
      Tag.where(name: name.strip.downcase).first_or_create!
    end
  end

  def all_tags
    self.tags.map(&:name).join(", ")
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
    %w[category sub_category business_model target_client taggings tags]
  end

  scope :text_search, ->(query) {
    where("name ILIKE :q OR description ILIKE :q OR location ILIKE :q", q: "%#{query}%")
  }

  def logo
    if logo_url.present?
      logo_url
    else
      # Default placeholder image
      "https://placehold.co/64x64?text=#{URI.encode_www_form_component(name[0])}"
    end
  end
end
