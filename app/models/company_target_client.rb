class CompanyTargetClient < ActiveRecord::Base
  belongs_to :company
  belongs_to :target_client
end
