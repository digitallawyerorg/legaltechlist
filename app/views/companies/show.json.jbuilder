json.extract! @company, :id, :slug, :name, :location, :founded_date, :category, :description, :main_url, :twitter_url, :angellist_url, :crunchbase_url, :linkedin_url, :facebook_url, :legalio_url, :status, :created_at, :updated_at
json.profile_url company_url(@company)
