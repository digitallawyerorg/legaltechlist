require "test_helper"
require "minitest/mock"

class CompanyFoundedDateBackfillServiceTest < ActiveSupport::TestCase
  test "fills founded_date from a registry-cited candidate and records provenance" do
    company = blank_year_company(name: "Company A", main_url: "https://companya.example")
    research = {
      "results" => [{ "url" => "https://opencorporates.com/companies/us/companya" }],
      "candidates" => [
        { "year" => "2018", "source_url" => "https://opencorporates.com/companies/us/companya", "evidence_text" => "Company A was incorporated in 2018." }
      ]
    }

    result = CompanyFoundedYearResearchService.stub(:call, research) do
      CompanyFoundedDateBackfillService.call(company: company)
    end

    assert_equal "filled", result["result"]
    assert_equal "2018", result["year"]
    assert_equal "registry", result["source_tier"]
    assert_equal "2018", company.reload.founded_date
    assert_equal "registry", company.founded_year_provenance["source_tier"]
    assert PipelineRun.where(run_type: "founded_date_backfill").where("details ->> 'company_id' = ?", company.id.to_s).exists?
  end

  test "skips when the cited evidence does not name the company" do
    company = blank_year_company(name: "Company B", main_url: "https://companyb.example")
    research = {
      "candidates" => [
        { "year" => "2010", "source_url" => "https://some-registry.example/x", "evidence_text" => "An unrelated firm was founded 2010." }
      ]
    }

    result = CompanyFoundedYearResearchService.stub(:call, research) do
      CompanyFoundedDateBackfillService.call(company: company)
    end

    assert_equal "skipped_no_source", result["result"]
    assert company.reload.founded_date.blank?
  end

  test "fills from a neutral registry aggregator that names the company in full" do
    company = blank_year_company(name: "APUA Innovation Oy", main_url: "https://apua.ai")
    research = {
      "candidates" => [
        { "year" => "2025", "source_url" => "https://woorati.com/en/companies/3567127-7/apua-innovation-oy", "evidence_text" => "APUA Innovation Oy Business ID: 3567127-7 Founded: 2025" }
      ]
    }

    result = CompanyFoundedYearResearchService.stub(:call, research) do
      CompanyFoundedDateBackfillService.call(company: company)
    end

    assert_equal "filled", result["result"]
    assert_equal "2025", result["year"]
    assert_equal "2025", company.reload.founded_date
  end

  test "rejects a same-name entity cited from a different domain (APUA trap)" do
    company = blank_year_company(name: "APUA Innovation Oy", main_url: "https://apua.ai")
    research = {
      "candidates" => [
        { "year" => "2015", "source_url" => "https://apualegal.com/about", "evidence_text" => "APUA Legal was founded in 2015." }
      ]
    }

    result = CompanyFoundedYearResearchService.stub(:call, research) do
      CompanyFoundedDateBackfillService.call(company: company)
    end

    assert_equal "skipped_no_source", result["result"]
    assert company.reload.founded_date.blank?
  end

  test "prefers a registry source over profile and owned when several are cited" do
    company = blank_year_company(name: "Tiered Co", main_url: "https://tieredco.example")
    research = {
      "results" => [
        { "url" => "https://opencorporates.com/companies/us/tieredco" },
        { "url" => "https://www.linkedin.com/company/tieredco" },
        { "url" => "https://tieredco.example/about" }
      ],
      "candidates" => [
        { "year" => "2020", "source_url" => "https://www.linkedin.com/company/tieredco", "evidence_text" => "Tiered Co · Founded 2020" },
        { "year" => "2018", "source_url" => "https://opencorporates.com/companies/us/tieredco", "evidence_text" => "Tiered Co incorporated 2018" },
        { "year" => "2019", "source_url" => "https://tieredco.example/about" }
      ]
    }

    result = CompanyFoundedYearResearchService.stub(:call, research) do
      CompanyFoundedDateBackfillService.call(company: company)
    end

    assert_equal "filled", result["result"]
    assert_equal "2018", result["year"]
    assert_equal "registry", result["source_tier"]
  end

  test "does nothing when founded_date is already present" do
    company = companies(:one)
    company.update_column(:founded_date, "2011")

    result = CompanyFoundedDateBackfillService.call(company: company)
    assert_equal "skipped_present", result["result"]
    assert_equal "2011", company.reload.founded_date
  end

  private

  def blank_year_company(name:, main_url:)
    attrs = companies(:one).attributes.except("id", "slug", "created_at", "updated_at", "founded_date", "founded_year_provenance")
    company = Company.new(attrs)
    company.name = name
    company.slug = name.parameterize
    company.main_url = main_url
    company.founded_date = ""
    company.skip_geocoding = true
    company.save!
    company
  end
end
