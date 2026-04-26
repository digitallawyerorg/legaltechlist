namespace :agent_reviews do
  desc "Create one manual company review PipelineRun without changing public company data. Optional: COMPANY_ID, QUEUE, REVIEWER, NOTES."
  task manual_company_review: :environment do
    company = if ENV["COMPANY_ID"].present?
      Company.find(ENV["COMPANY_ID"])
    else
      scope = case ENV.fetch("QUEUE", "weak_description")
      when "missing_url" then Company.missing_main_url
      when "duplicate_domain" then Company.duplicate_domain_candidates
      when "duplicate_name" then Company.duplicate_name_candidates
      when "needs_review" then Company.needs_review
      when "all" then Company.all
      else Company.weak_description
      end

      scope.order(:id).first || Company.order(:id).first
    end

    abort "No company found for manual review." unless company

    run = ManualCompanyReviewService.call(
      company: company,
      reviewer: ENV["REVIEWER"],
      notes: ENV["NOTES"]
    )

    puts "Created manual company review run_id=#{run.id} company_id=#{company.id} company_name=#{company.name.inspect} status=#{run.status}"
    puts "Mode: no public company fields were changed."
  end
end
