module Mcp
  module Tools
    # Shared helpers for all curator tools: actor resolution, JSON responses,
    # company lookup/serialization, and audit logging to PipelineRun.
    class BaseTool < MCP::Tool
      # Input schema for the allowlisted company fields a curator may set on a
      # proposal (update_proposal) or an existing-company edit (propose_company_update).
      # Keys mirror CompanyProposal::EDITABLE_COMPANY_FIELDS.
      CHANGE_FIELD_SCHEMA = {
        name: { type: "string" },
        main_url: { type: "string" },
        location: { type: "string" },
        founded_date: { type: "string", description: "ISO date (YYYY-MM-DD) or year." },
        status: { type: "string", description: "Lifecycle status, e.g. active, acquired, defunct." },
        description: { type: "string", description: "Neutral, encyclopedic description fit for public display (no marketing language or internal notes)." },
        category_id: { type: "integer", description: "Primary category id from get_taxonomy." },
        secondary_category_id: { type: "integer", description: "Secondary category id from get_taxonomy." },
        business_model_id: { type: "integer" },
        business_model_ids: { type: "array", items: { type: "integer" }, description: "Business/revenue model ids from get_taxonomy." },
        target_client_id: { type: "integer" },
        target_client_ids: { type: "array", items: { type: "integer" }, description: "Target client ids from get_taxonomy." },
        all_tags: { type: "string", description: "Comma-separated canonical tag names from get_taxonomy." },
        crunchbase_url: { type: "string" },
        linkedin_url: { type: "string" },
        total_funding_amount_usd: { type: "number" },
        funding_status: { type: "string" },
        number_of_funding_rounds: { type: "integer" },
        founders: { type: "string" },
        source: { type: "string" },
        source_url: { type: "string" }
      }.freeze

      class << self
        def curator
          Mcp::CuratorActor.admin_user!
        end

        # Keep only allowlisted, editable company fields from a caller-supplied hash.
        def slice_editable_changes(changes)
          (changes || {}).transform_keys(&:to_s).slice(*CompanyProposal::EDITABLE_COMPANY_FIELDS)
        end

        def json_response(payload)
          MCP::Tool::Response.new([{ type: "text", text: payload.to_json }])
        end

        def error_response(payload)
          MCP::Tool::Response.new([{ type: "text", text: payload.to_json }], error: true)
        end

        def not_found(message)
          error_response("error" => message)
        end

        def find_company(identifier)
          value = identifier.to_s.strip
          Company.find_by(slug: value) || (value.match?(/\A\d+\z/) ? Company.find_by(id: value.to_i) : nil)
        end

        def profile_url(company)
          "#{Mcp::CuratorPolicy.site_url}/companies/#{company.slug}"
        end

        def admin_proposal_url(proposal)
          SlackNotifier.admin_proposal_url(proposal)
        end

        def company_summary(company)
          {
            "id" => company.id,
            "slug" => company.slug,
            "name" => company.name,
            "profile_url" => profile_url(company),
            "main_url" => company.main_url,
            "category" => company.category&.name,
            "secondary_category" => company.secondary_category&.name,
            "status" => company.status,
            "visible" => company.visible,
            "quality_status" => company.quality_status,
            "verification_verdict" => company.verification_verdict,
            "human_reviewed_at" => company.human_reviewed_at&.iso8601,
            "founded_date" => company.founded_date,
            "location" => company.display_location
          }
        end

        def audit!(action:, summary:, records_processed: 0, details: {})
          PipelineRun.create!(
            name: "Curator MCP: #{action}",
            run_type: "curator_mcp",
            status: "succeeded",
            agent_name: "ClaudeTagCurator",
            records_processed: records_processed,
            started_at: Time.current,
            finished_at: Time.current,
            details: { "action" => action, "actor" => "claude_tag", "summary" => summary }.merge(details.deep_stringify_keys)
          )
        rescue StandardError => e
          Rails.logger.debug("[CuratorMCP] audit failed for #{action}: #{e.message}")
          nil
        end
      end
    end
  end
end
