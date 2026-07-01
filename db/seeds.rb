MethodologyHelper::TARGET_CLIENTS.each do |row|
  TargetClient.find_or_create_by!(name: row[:name]) do |client|
    client.description = row[:definition]
  end
end

BusinessModel.create([
  { name: "Subscription", description: "Monthly or annual recurring revenue, seat-based pricing, or tiered plans" },
  { name: "Usage-Based", description: "Consumption-based billing for API calls, storage, compute, or per-unit usage" },
  { name: "Transaction Fee", description: "Commissions, take rates, or fees on payments and marketplace transactions" },
  { name: "Services", description: "Hourly, project, retainer, or managed-service delivery by people" },
  { name: "Licensing", description: "Software or IP licensing fees and royalties" },
  { name: "Advertising", description: "Advertising, sponsorships, and ad-supported revenue" },
  { name: "Commerce", description: "One-time product sales, physical or digital" },
  { name: "Success Fee", description: "Performance-based fees such as recruiting, M&A, or contingency pricing" },
  { name: "Grants & Subsidies", description: "Grants, donations, or public subsidies (legal aid, A2J, nonprofits)" },
  { name: "Other", description: "Revenue models that do not fit the categories above" }
])

unless AdminUser.exists?(email: 'admin@example.com')
  AdminUser.create!(email: 'admin@example.com', password: 'password', password_confirmation: 'password')
end
