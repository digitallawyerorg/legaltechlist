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
  attribute :all_tags, :string
  attribute :crunchbase_url, :string
  attribute :linkedin_url, :string
  attribute :twitter_url, :string
  attribute :facebook_url, :string
  attribute :angellist_url, :string
  attribute :legalio_url, :string
  attribute :logo_url, :string

  validates :contact_email, :name, :main_url, :location, :founded_date, :category_id, :description, :status, presence: true
  validate :revenue_models_present
  validate :target_clients_present

  def self.from_params(params)
    permitted = params.require(:company_contribution).permit(
      :contact_name, :contact_email, :name, :main_url, :location, :founded_date,
      :category_id, :description, :status, :all_tags, :crunchbase_url, :linkedin_url,
      :twitter_url, :facebook_url, :angellist_url, :legalio_url, :logo_url,
      business_model_ids: [], target_client_ids: []
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
      "all_tags" => all_tags.to_s.strip.presence,
      "crunchbase_url" => crunchbase_url.to_s.strip.presence,
      "linkedin_url" => linkedin_url.to_s.strip.presence,
      "twitter_url" => twitter_url.to_s.strip.presence,
      "facebook_url" => facebook_url.to_s.strip.presence,
      "angellist_url" => angellist_url.to_s.strip.presence,
      "legalio_url" => legalio_url.to_s.strip.presence,
      "logo_url" => logo_url.to_s.strip.presence,
      "source" => "User contribution",
      "source_url" => main_url.to_s.strip.presence
    }.compact
  end

  def source_payload
    proposed_changes.merge(
      "contact_name" => contact_name.to_s.strip.presence,
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
end
