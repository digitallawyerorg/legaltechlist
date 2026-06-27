json.query @query
json.total_count @total_count
json.companies @companies do |company|
  json.id company.id
  json.name company.name
  json.subtitle website_display_label(company.main_url).presence || company.category&.name
  json.url company_path(company)
  json.logo company.logo
end
