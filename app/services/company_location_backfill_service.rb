class CompanyLocationBackfillService
  PLACEHOLDER_LOCATIONS = [
    "Location unknown",
    "No location yet",
    "Nowhere",
    "Global",
    "na"
  ].freeze

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(company:, dry_run: true, overwrite: false)
    @company = company
    @dry_run = dry_run
    @overwrite = overwrite
  end

  def call
    return skip_result("blank_location") if company.location.blank?
    return skip_result("placeholder_location") if placeholder_location?(company.location)
    return skip_result("already_structured") if structured? && !overwrite

    parsed = LocationCountryResolver.parse(company.location)
    return skip_result("country_unresolved") if parsed[:country].blank?

    result = {
      "company_id" => company.id,
      "location" => company.location,
      "country" => parsed[:country],
      "city" => parsed[:city],
      "applied" => false,
      "dry_run" => dry_run
    }

    unless dry_run
      company.update_columns(
        country: parsed[:country],
        city: parsed[:city],
        updated_at: company.updated_at
      )
      result["applied"] = true
    end

    result["action"] = dry_run ? "would_apply" : "applied"
    result
  end

  private

  attr_reader :company, :dry_run, :overwrite

  def structured?
    company.country.present?
  end

  def placeholder_location?(location)
    normalized = location.to_s.strip
    return true if normalized.blank?

    PLACEHOLDER_LOCATIONS.any? { |placeholder| normalized.casecmp?(placeholder) }
  end

  def skip_result(reason)
    {
      "company_id" => company.id,
      "location" => company.location,
      "action" => "skipped_#{reason}",
      "applied" => false,
      "dry_run" => dry_run
    }
  end
end
