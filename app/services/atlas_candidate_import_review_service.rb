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
    AtlasCandidateNormalizerService.call(row)
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
