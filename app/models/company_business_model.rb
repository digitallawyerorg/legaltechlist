class CompanyBusinessModel < ActiveRecord::Base
  belongs_to :company
  belongs_to :business_model

  validates :company_id, uniqueness: { scope: :business_model_id }
end
