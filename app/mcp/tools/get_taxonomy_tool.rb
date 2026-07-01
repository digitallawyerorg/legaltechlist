module Mcp
  module Tools
    class GetTaxonomyTool < BaseTool
      tool_name "get_taxonomy"
      title "Get taxonomy"
      description "Return the controlled vocabulary used to classify companies: categories, business/revenue models, target clients, and canonical tags. Always use these exact ids and tag names when proposing or editing companies; never invent new categories, models, clients, or tags."
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, title: "Get taxonomy")
      input_schema(properties: {}, required: [])

      def self.call(server_context:)
        json_response(
          "categories" => id_names(Category.order(:name)),
          "business_models" => id_names(BusinessModel.canonical.order(:name)),
          "target_clients" => id_names(TargetClient.canonical.order(:name)),
          "tags" => Tag.discoverable_names,
          "usage" => "category_id and secondary_category_id take category ids; business_model_ids and target_client_ids are arrays of ids; all_tags is a comma-separated string built from the tag names above."
        )
      end

      def self.id_names(relation)
        relation.pluck(:id, :name).map { |id, name| { "id" => id, "name" => name } }
      end
    end
  end
end
