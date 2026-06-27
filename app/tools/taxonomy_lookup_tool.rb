class TaxonomyLookupTool < RubyLLM::Tool
  description "Return available TechIndex taxonomy values and current company taxonomy. Read-only."

  param :company_id, type: :integer, desc: "Company id to inspect.", required: false

  def execute(company_id: nil)
    company = Company.find_by(id: company_id) if company_id.present?

    {
      "company_id" => company_id,
      "current" => current_taxonomy(company),
      "available" => {
        "categories" => Category.order(:name).pluck(:name),
        "revenue_models" => BusinessModel.order(:name).pluck(:name),
        "target_clients" => TargetClient.order(:name).pluck(:name)
      },
      "read_only" => true
    }
  end

  private

  def current_taxonomy(company)
    return {} unless company

    {
      "category" => company.category&.name,
      "revenue_models" => company.revenue_model_names,
      "target_client" => company.target_client&.name
    }
  end
end
