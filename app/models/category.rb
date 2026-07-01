class Category < ActiveRecord::Base
  include UrlSlug

  has_many :companies
  has_many :sub_categories

  accepts_nested_attributes_for :companies
  
  def sub_category
    SubCategory.where(:category => id)
  end

  def self.ransackable_attributes(auth_object = nil)
    ["created_at", "description", "id", "name", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["companies", "sub_categories"]
  end
end
