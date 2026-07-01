class TargetClient < ActiveRecord::Base
  include UrlSlug

  has_many :companies

  scope :canonical, -> {
    names = TaxonomyNormalizationService::CANONICAL_TARGET_CLIENTS
    where(id: unscoped.where(name: names).group(:name).select("MIN(id)"))
  }

  accepts_nested_attributes_for :companies
  
  def self.ransackable_attributes(auth_object = nil)
    %w[id name description created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[companies]
  end
end
