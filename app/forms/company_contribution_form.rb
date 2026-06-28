class CompanyContributionForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :contact_name, :string
  attribute :contact_email, :string
  attribute :name, :string
  attribute :main_url, :string
  attribute :location, :string
  attribute :founded_date, :string
  attribute :category_id, :integer
  attribute :description, :string
  attribute :status, :string
  attribute :business_model_ids, default: -> { [] }
  attribute :target_client_ids, default: -> { [] }
  attribute :tag_names, default: -> { [] }
  attribute :crunchbase_url, :string
  attribute :linkedin_url, :string
  attribute :twitter_url, :string
  attribute :facebook_url, :string
  attribute :legalio_url, :string
  attribute :legaltech_atlas_url, :string
  attribute :logo_url, :string

  MIN_DESCRIPTION_LENGTH = UserSubmissionProtection::MIN_CONTRIBUTION_DESCRIPTION_LENGTH

  validates :contact_name, :contact_email, :name, :main_url, :location, :founded_date, :category_id, :description, :status, presence: true
  validates :description, length: { minimum: MIN_DESCRIPTION_LENGTH, too_short: "must be at least %{count} characters" }
  validate :revenue_models_present
  validate :target_clients_present
  validate :tags_present
  validate :tags_must_be_discoverable

  def self.from_params(params)
    permitted = params.require(:company_contribution).permit(
      :contact_name, :contact_email, :name, :main_url, :location, :founded_date,
      :category_id, :description, :status, :crunchbase_url, :linkedin_url,
      :twitter_url, :facebook_url, :legalio_url, :legaltech_atlas_url, :logo_url,
      business_model_ids: [], target_client_ids: [], tag_names: []
    )
    new(permitted.to_h)
  end

  def proposed_changes
    {
      "name" => name.to_s.strip,
      "main_url" => main_url.to_s.strip,
      "location" => location.to_s.strip,
      "founded_date" => founded_date.to_s.strip,
      "category_id" => category_id,
      "description" => description.to_s.strip,
      "status" => status.to_s.strip.downcase,
      "business_model_ids" => normalized_business_model_ids,
      "business_model_id" => normalized_business_model_ids.first,
      "target_client_ids" => normalized_target_client_ids,
      "target_client_id" => normalized_target_client_ids.first,
      "all_tags" => normalized_tag_names.join(", ").presence,
      "crunchbase_url" => crunchbase_url.to_s.strip.presence,
      "linkedin_url" => linkedin_url.to_s.strip.presence,
      "twitter_url" => twitter_url.to_s.strip.presence,
      "facebook_url" => facebook_url.to_s.strip.presence,
      "legalio_url" => legalio_url.to_s.strip.presence,
      "legaltech_atlas_url" => legaltech_atlas_url.to_s.strip.presence,
      "logo_url" => logo_url.to_s.strip.presence,
      "source" => "User contribution",
      "source_url" => main_url.to_s.strip.presence
    }.compact
  end

  def source_payload
    proposed_changes.merge(
      "contact_name" => contact_name.to_s.strip,
      "contact_email" => contact_email.to_s.strip,
      "submission_channel" => "public_contribute_form"
    )
  end

  private

  def normalized_business_model_ids
    @normalized_business_model_ids ||= Array(business_model_ids).map(&:presence).compact.map(&:to_i).uniq
  end

  def normalized_target_client_ids
    @normalized_target_client_ids ||= Array(target_client_ids).map(&:presence).compact.map(&:to_i).uniq
  end

  def revenue_models_present
    errors.add(:business_model_ids, "can't be blank") if normalized_business_model_ids.empty?
  end

  def target_clients_present
    errors.add(:target_client_ids, "can't be blank") if normalized_target_client_ids.empty?
  end

  def tags_present
    errors.add(:tag_names, "can't be blank") if normalized_tag_names.empty?
  end

  def tags_must_be_discoverable
    invalid = Array(tag_names).map(&:presence).compact.reject { |name| TagTaxonomyService.assignable?(name) }
    return if invalid.empty?

    errors.add(:tag_names, "must be selected from the curated tag list")
  end

  def normalized_tag_names
    @normalized_tag_names ||= TagTaxonomyService.filter_assignable(tag_names)
  end
end
