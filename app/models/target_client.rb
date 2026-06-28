class TargetClient < ActiveRecord::Base
  has_many :companies

  scope :canonical, -> { where(name: TaxonomyNormalizationService::CANONICAL_TARGET_CLIENTS) }

  accepts_nested_attributes_for :companies
  
  def self.ransackable_attributes(auth_object = nil)
    %w[id name description created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[companies]
  end
end
