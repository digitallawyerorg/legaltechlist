json.array!(@companies) do |company|
  json.extract! company, :id, :slug, :name, :location, :founded_date, :category, :description, :main_url, :twitter_url, :angellist_url, :crunchbase_url, :linkedin_url, :facebook_url, :legalio_url, :status
  json.profile_url company_url(company)
  json.url company_url(company, format: :json)
end
