module Admin
  class AgentReviewsController < BaseController
    SAFE_APPLY_FIELDS = %w[
      quality_status
      verification_verdict
      quality_score
      canonical_domain
      fingerprint
    ].freeze

    def index
      @agent_reviews = PipelineRun.where.not(details: nil).recent.page(params[:page]).per(25)
    end

    def show
      load_review
    end

    def apply
      load_review
      return redirect_to custom_admin_agent_review_path(@pipeline_run), alert: "This review is not linked to a company." unless @company

      selected_fields = Array(params[:fields]) & SAFE_APPLY_FIELDS
      return redirect_to custom_admin_agent_review_path(@pipeline_run), alert: "Select at least one safe field to apply." if selected_fields.empty?

      applied_changes = selected_fields.each_with_object({}) do |field, changes|
        next unless @proposed_corrections.key?(field)

        value = cast_proposed_value(field, @proposed_corrections[field])
        @company.public_send("#{field}=", value)
        changes[field] = value
      end

      return redirect_to custom_admin_agent_review_path(@pipeline_run), alert: "No selected fields were available on this review." if applied_changes.empty?

      @company.save!
      record_decision!("applied", applied_changes: applied_changes, selected_fields: selected_fields)

      redirect_to custom_admin_agent_review_path(@pipeline_run), notice: "Applied #{applied_changes.keys.to_sentence} to #{@company.name}."
    end

    def reject
      load_review
      record_decision!("rejected")

      redirect_to custom_admin_agent_review_path(@pipeline_run), notice: "Agent review rejected without changing company data."
    end

    def follow_up
      load_review
      record_decision!("needs_follow_up")

      redirect_to custom_admin_agent_review_path(@pipeline_run), notice: "Agent review marked for follow-up."
    end

    private

    def load_review
      @pipeline_run = PipelineRun.find(params[:id])
      @details = @pipeline_run.details || {}
      @company = Company.find_by(id: @details["company_id"])
      @evidence = Array(@details["evidence"])
      @tool_results = @details["tool_results"] || {}
      @proposed_corrections = @details["proposed_corrections"] || @details["proposed_changes"] || {}
      @safe_proposed_corrections = @proposed_corrections.slice(*SAFE_APPLY_FIELDS)
      @review_only_proposed_corrections = @proposed_corrections.except(*SAFE_APPLY_FIELDS)
      @description_draft = @details["description_draft"] || {}
      @description_critic = @details["description_critic"] || {}
      @review_coordinator = @details["review_coordinator"] || {}
      @risks = Array(@details["risks"])
    end

    def cast_proposed_value(field, value)
      return value.to_i if field == "quality_score" && value.present?

      value
    end

    def record_decision!(decision, applied_changes: {}, selected_fields: [])
      details = @details.deep_dup
      details["admin_decision"] = {
        "decision" => decision,
        "admin_user_id" => current_admin_user.id,
        "admin_user_email" => current_admin_user.email,
        "decided_at" => Time.current.utc.iso8601,
        "selected_fields" => selected_fields,
        "applied_changes" => applied_changes
      }

      @pipeline_run.update!(details: details)
    end
  end
end
