module Mcp
  module Tools
    class DiscoverCompaniesTool < BaseTool
      tool_name "discover_companies"
      title "Discover companies"
      description "Run LLM web-search discovery for new legal-tech companies. Defaults to a dry run; set queue_proposals=true to create discovery proposals for review."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, title: "Discover companies")
      input_schema(
        properties: {
          discovery_type: { type: "string", enum: CompanyDiscoveryService::DISCOVERY_TYPES, description: "One of: #{CompanyDiscoveryService::DISCOVERY_TYPES.join(', ')}." },
          seed: { type: "string", description: "Seed value for the discovery type (category name, competitor company name, year, country, or funding year)." },
          limit: { type: "integer", description: "Max companies to search for (capped by MCP_CURATOR_MAX_DISCOVERY_LIMIT)." },
          queue_proposals: { type: "boolean", description: "If true, create discovery proposals for absent candidates (requires a live search, not a dry run)." }
        },
        required: ["discovery_type"]
      )

      def self.call(server_context:, discovery_type:, seed: nil, limit: 10, queue_proposals: false)
        unless CompanyDiscoveryService::DISCOVERY_TYPES.include?(discovery_type.to_s)
          return not_found("Unknown discovery_type '#{discovery_type}'. Use one of: #{CompanyDiscoveryService::DISCOVERY_TYPES.join(', ')}")
        end

        queue = ActiveModel::Type::Boolean.new.cast(queue_proposals)
        capped = [[limit.to_i, 1].max, Mcp::CuratorPolicy.max_discovery_limit].min

        options = {
          discovery_type: discovery_type.to_s,
          limit: capped,
          dry_run: !queue,
          queue_proposals: queue,
          reviewer: "claude@techindex",
          notes: "Claude Tag curator discovery",
          admin_user: curator
        }.merge(seed_option(discovery_type.to_s, seed))

        run = CompanyDiscoveryService.call(**options)
        details = run.details || {}

        audit!(
          action: "discover_companies",
          summary: "Discovery #{discovery_type} (#{seed}) run ##{run.id}",
          records_processed: run.records_processed,
          details: { "run_id" => run.id, "queue_proposals" => queue }
        )

        json_response(
          "run_id" => run.id,
          "discovery_type" => discovery_type,
          "seed" => seed,
          "dry_run" => !queue,
          "summary" => details["summary"],
          "queued_proposals_count" => Array(details["proposal_results"]).size,
          "candidates_preview" => Array(details["candidates"]).first(20).map { |c| c.slice("name", "website", "status") }
        )
      rescue ArgumentError, CompanyDiscoveryService::CostLimitExceededError => e
        not_found(e.message)
      end

      def self.seed_option(discovery_type, seed)
        case discovery_type
        when "category" then { category: seed }
        when "competitors" then { company_name: seed }
        when "year" then { year: seed }
        when "country" then { country: seed }
        when "funding_year" then { funding_year: seed }
        else {}
        end
      end
    end
  end
end
