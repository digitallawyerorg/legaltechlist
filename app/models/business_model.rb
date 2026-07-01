class BusinessModel < ActiveRecord::Base
  include UrlSlug

  has_many :company_business_models, dependent: :destroy
  has_many :companies, through: :company_business_models

  scope :canonical, -> { where(name: MethodologyHelper::REVENUE_MODEL_NAMES) }

  accepts_nested_attributes_for :companies
  
  def self.ransackable_attributes(auth_object = nil)
    %w[id name description created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[companies]
  end
end
