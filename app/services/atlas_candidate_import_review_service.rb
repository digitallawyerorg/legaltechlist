require "csv"

class AtlasCandidateImportReviewService
  RUN_TYPE = "atlas_candidate_import_review".freeze
  AGENT_NAME = "AtlasCandidateImportReviewService".freeze
  DEFAULT_LIMIT = 100
  DEFAULT_MAX_LIMIT = 1_000

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(file:, reviewer: nil, notes: nil, limit: DEFAULT_LIMIT, max_limit: DEFAULT_MAX_LIMIT)
    @file = file
    @reviewer = reviewer
    @notes = notes
    @limit = limit.to_i
    @max_limit = max_limit.to_i
  end

  def call
    validate_options!
    run = PipelineRun.create!(
      name: "Atlas candidate import review",
      run_type: RUN_TYPE,
      status: "pending",
      agent_name: AGENT_NAME
    )

    run.mark_running!
    run.mark_succeeded!(records_processed: candidate_reviews.size, details: details_payload)
    run
  rescue StandardError => e
    run&.mark_failed!(e.message, details: failure_payload(e))
    raise
  ensure
    close_file_handle
  end

  private

  attr_reader :file, :reviewer, :notes, :limit, :max_limit

  def validate_options!
    raise ArgumentError, "CSV file is required" unless file.present?
    raise ArgumentError, "limit must be greater than 0" unless limit.positive?
    raise ArgumentError, "limit #{limit} exceeds max_limit #{max_limit}" if limit > max_limit
  end

  def details_payload
    {
      "reviewer" => reviewer,
      "notes" => notes,
      "mode" => "candidate_import_review_no_public_writes",
      "source" => "legaltechatlas_csv",
      "limit" => limit,
      "max_limit" => max_limit,
      "summary" => summary,
      "candidates" => candidate_reviews,
      "created_at" => Time.current.utc.iso8601,
      "completed_at" => Time.current.utc.iso8601
    }
  end

  def failure_payload(error)
    {
      "reviewer" => reviewer,
      "notes" => notes,
      "mode" => "candidate_import_review_no_public_writes",
      "source" => "legaltechatlas_csv",
      "limit" => limit,
      "max_limit" => max_limit,
      "error_class" => error.class.name,
      "failed_at" => Time.current.utc.iso8601
    }
  end

  def summary
    @summary ||= {
      "reviewed_rows" => candidate_reviews.size,
      "absent_candidates" => candidate_reviews.count { |candidate| candidate["status"] == "absent_candidate" },
      "existing_name_matches" => candidate_reviews.count { |candidate| candidate["name_matches"].any? },
      "existing_domain_matches" => candidate_reviews.count { |candidate| candidate["domain_matches"].any? },
      "skipped_rows" => skipped_rows.size,
      "warning" => "Candidates are review-only. Source descriptions must not be copied into public TechIndex descriptions."
    }
  end

  def candidate_reviews
    @candidate_reviews ||= parsed_rows.first(limit).map { |row| candidate_review(row) }
  end

  def candidate_review(row)
    name = candidate_name(row)
    website = clean_url(row["Website"])
    canonical_domain = Company.canonical_domain_for(website)
    normalized_name = Company.normalized_name_value(name)
    name_matches = name_match_payloads(normalized_name)
    domain_matches = domain_match_payloads(canonical_domain)

    {
      "status" => name_matches.any? || domain_matches.any? ? "existing_or_possible_duplicate" : "absent_candidate",
      "name" => name,
      "normalized_name" => normalized_name,
      "website" => website,
      "canonical_domain" => canonical_domain,
      "crunchbase_url" => clean_url(row["Organization Name URL"]),
      "linkedin_url" => clean_url(row["LinkedIn"]),
      "location" => row["Headquarters Location"].to_s.strip.presence,
      "founded_date" => row["Founded Date"].to_s.strip.presence,
      "operating_status" => row["Operating Status"].to_s.strip.presence,
      "company_type" => row["Company Type"].to_s.strip.presence,
      "industries" => split_list(row["Industries"]),
      "funding_amount_usd" => row["Total Funding Amount (in USD)"].to_s.strip.presence,
      "source_description" => row["Description"].to_s.strip.presence,
      "source_description_policy" => "Do not copy into TechIndex. Use only as evidence for a new neutral description after human review.",
      "name_matches" => name_matches,
      "domain_matches" => domain_matches,
      "recommended_action" => recommended_action(name_matches, domain_matches)
    }
  end

  def parsed_rows
    @parsed_rows ||= begin
      rows = []
      csv = CSV.new(file_io, headers: true, encoding: "UTF-8")
      csv.each_with_index do |row, index|
        if candidate_name(row).blank?
          skipped_rows << { "row_number" => index + 2, "reason" => "Missing organization name." }
          next
        end

        rows << row
      end
      rows
    end
  end

  def skipped_rows
    @skipped_rows ||= []
  end

  def candidate_name(row)
    row["Organization Name"].to_s.strip
  end

  def name_match_payloads(normalized_name)
    return [] if normalized_name.blank?

    Company.where.not(name: [nil, ""]).select { |company| company.normalized_name == normalized_name }.first(10).map { |company| company_payload(company) }
  end

  def domain_match_payloads(canonical_domain)
    return [] if canonical_domain.blank?

    Company.where.not(main_url: [nil, ""]).select { |company| (company.canonical_domain.presence || company.canonical_main_domain) == canonical_domain }.first(10).map { |company| company_payload(company) }
  end

  def company_payload(company)
    {
      "id" => company.id,
      "name" => company.name,
      "main_url" => company.main_url,
      "canonical_domain" => company.canonical_domain.presence || company.canonical_main_domain,
      "visible" => company.visible,
      "quality_status" => company.quality_status
    }
  end

  def recommended_action(name_matches, domain_matches)
    return "Review existing domain match before importing." if domain_matches.any?
    return "Review existing name match before importing." if name_matches.any?

    "Candidate appears absent; queue for human candidate-import review before creating any company record."
  end

  def split_list(value)
    value.to_s.split(",").map(&:strip).compact_blank
  end

  def clean_url(url)
    value = url.to_s.strip
    return nil if value.blank?

    value.match?(%r{\Ahttps?://}i) ? value : "https://#{value}"
  end

  def file_io
    @file_io ||= begin
      io = if file.respond_to?(:tempfile)
        file.tempfile
      elsif file.respond_to?(:path)
        File.open(file.path, "r")
      else
        File.open(file.to_s, "r")
      end
      io.rewind
      io
    end
  end

  def close_file_handle
    return unless defined?(@file_io)
    return if file.respond_to?(:tempfile)

    @file_io.close
  end
end
