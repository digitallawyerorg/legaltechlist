require "csv"

class CompanyImportSeedService
  SOURCE = CompanyCandidateImportService::SOURCE

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(file:, filename: nil, reviewer: nil, notes: nil, limit: nil)
    @file = file
    @filename = filename.presence || File.basename(file.to_s)
    @reviewer = reviewer
    @notes = notes
    @limit = limit&.to_i
  end

  def call
    run = CompanyImportRun.create!(
      source: SOURCE,
      filename: filename,
      reviewer: reviewer,
      notes: notes,
      status: "pending"
    )

    rows = parsed_rows
    rows = rows.first(limit) if limit.present?
    rows.each { |row_number, row| create_import_row!(run, row_number, row) }
    run.update!(total_rows: run.company_import_rows.count)
    run.refresh_summary!
    run
  ensure
    close_file_handle
  end

  private

  attr_reader :file, :filename, :reviewer, :notes, :limit

  def create_import_row!(run, row_number, row)
    candidate = AtlasCandidateNormalizerService.call(row)
    run.company_import_rows.create!(
      row_number: row_number,
      source_identifier: source_identifier(candidate),
      canonical_domain: candidate["canonical_domain"],
      source_payload: row.to_h,
      candidate_payload: candidate
    )
  end

  def parsed_rows
    rows = []
    CSV.new(file_io, headers: true, encoding: "UTF-8").each_with_index do |row, index|
      next if row["Organization Name"].to_s.strip.blank?

      rows << [index + 1, row]
    end
    rows
  end

  def source_identifier(candidate)
    candidate["canonical_domain"].presence || Company.normalized_name_value(candidate["name"])
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
