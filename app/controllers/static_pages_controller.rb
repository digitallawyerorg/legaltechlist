require 'csv'
require 'axlsx'

class StaticPagesController < ApplicationController
  def self.stage_mapping
    {
      'Pre-seed' => 'Seed',
      'Seed' => 'Seed',
      'Series A' => 'Early Stage',
      'Series B' => 'Early Stage',
      'Series C' => 'Late Stage',
      'Series D' => 'Late Stage',
      'Series E' => 'Late Stage',
      'Series F' => 'Late Stage',
      'Series G' => 'Late Stage',
      'Series H' => 'Late Stage',
      'Private Equity' => 'Private Equity',
      'Post-IPO' => 'Public',
      'Public' => 'Public',
      'M&A' => 'Acquired',
      'Acquired' => 'Acquired'
    }
  end

  def home
  	@tags = Tag.limit(50)
    @home_category_counts = Rails.cache.fetch("home/visible_category_counts/#{company_cache_version}/#{category_cache_version}", expires_in: 10.minutes) do
      Category.where.not(name: "Unknown")
              .where.not(id: [12, 13, 14])
              .left_joins(:companies)
              .where(companies: { visible: true })
              .group("categories.id")
              .count
    end
    @home_categories = Category.where.not(name: "Unknown")
                               .where.not(id: [12, 13, 14])
                               .to_a
                               .sort_by { |category| -@home_category_counts.fetch(category.id, 0) }
  end

  def about
  end

  def statistics
  end

  def methodology
  end

  def total_companies
    @growth_view = growth_view_param
    @table_data = total_companies_table_data(start_year: 2000, end_year: Time.current.year)

    # Prepare chart data
    @chart_data = {
      name: 'Total Companies',
      data: @table_data.map { |d| [d[:year], d[:total_companies]] }
    }

    respond_to do |format|
      format.html
      format.csv do
        csv_data = CSV.generate do |csv|
          csv << ["Year", "New Companies", "Total Companies", "Growth Rate (%)"]
          @table_data.each do |data|
            csv << [
              data[:year],
              data[:new_companies],
              data[:total_companies],
              data[:growth_rate].round(1)
            ]
          end
        end
        send_data csv_data,
                  filename: "total_companies_evolution.csv",
                  type: 'text/csv',
                  disposition: 'attachment'
      end
      format.xlsx do
        p = Axlsx::Package.new
        wb = p.workbook
        wb.add_worksheet(name: "Total Companies") do |sheet|
          sheet.add_row ["Year", "New Companies", "Total Companies", "Growth Rate (%)"]
          @table_data.each do |data|
            sheet.add_row [
              data[:year],
              data[:new_companies],
              data[:total_companies],
              data[:growth_rate].round(1)
            ]
          end
        end
        send_data p.to_stream.read,
                  filename: "total_companies_evolution.xlsx",
                  type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                  disposition: 'attachment'
      end
    end
  end

  def total_companies_all_time
    redirect_to statistics_total_companies_path(params.permit(:view)), status: :moved_permanently
  end

  def companies_founded
    counts_by_year = visible_company_counts_by_year
    pre_2000_count = counts_by_year.sum { |year, count| year < 2000 ? count : 0 }

    @table_data = counts_by_year.select { |year, _count| year.between?(2000, Time.current.year) }
                                .sort
                                .map do |year, count|
      {
        year: year,
        new_companies: count,
        growth_rate: calculate_growth_rate_from_counts(year, count, counts_by_year)
      }
    end

    # Calculate cumulative total for each year, including pre-2000 companies
    running_total = pre_2000_count
    @table_data.each do |data|
      running_total += data[:new_companies]
      data[:total_companies] = running_total
    end

    respond_to do |format|
      format.html { redirect_to statistics_total_companies_path(view: 'annual') }
      format.csv { send_data generate_companies_founded_csv, filename: "companies_founded.csv" }
      format.xlsx { send_data generate_companies_founded_xlsx, filename: "companies_founded.xlsx" }
    end
  end

  def download_companies_founded
    redirect_to statistics_companies_founded_path(format: :csv)
  end

  def category_evolution
    cache_key = "statistics/category_evolution/#{company_cache_version}/#{category_cache_version}"
    if (cached_data = Rails.cache.read(cache_key))
      @table_data = cached_data[:table_data]
      @summary_data = cached_data[:summary_data]
    else
    # Get all companies with their categories and founding years
    companies = Company.includes(:category)
                      .where(visible: true)
                      .where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
                             '2000',
                             Time.current.year.to_s,
                             '^\d{4}$')
                      .where.not(category_id: nil)

    # Get the year range
    start_year = 2000
    end_year = Time.current.year
    years = (start_year..end_year).to_a

    # Initialize data structures
    categories = Category.where.not(name: 'Unknown')
    category_data = {}

    # Initialize yearly data for each category
    categories.each do |category|
        category_data[category.id] = {
            category: category.name,
            yearly_data: years.map { |year| [year.to_s, 0] }.to_h,
            total_companies: 0
        }
    end

    # Calculate cumulative companies per category per year
    companies.each do |company|
        next if company.category.name == 'Unknown'
        year = company.founded_date.to_i
        category_id = company.category_id

        # Update yearly count for the category
        (year..end_year).each do |y|
            category_data[category_id][:yearly_data][y.to_s] += 1
        end
        category_data[category_id][:total_companies] += 1
    end

    # Calculate total companies per year for market share
    total_companies = category_data.values.sum { |d| d[:total_companies] }

    # Prepare final data structures
    @table_data = category_data.values.sort_by { |d| -d[:total_companies] }

    @summary_data = @table_data.map do |data|
        prev_year = (end_year - 1).to_s
        current_year = end_year.to_s

        growth_rate = if data[:yearly_data][prev_year] > 0
            ((data[:yearly_data][current_year] - data[:yearly_data][prev_year]) / data[:yearly_data][prev_year].to_f) * 100
        else
            0
        end

        {
            category: data[:category],
            total_companies: data[:total_companies],
            growth_rate: growth_rate,
            market_share: (data[:total_companies] / total_companies.to_f) * 100
        }
    end

    Rails.cache.write(cache_key, { table_data: @table_data, summary_data: @summary_data }, expires_in: 10.minutes)
    end

    respond_to do |format|
        format.html
        format.csv { send_data generate_category_evolution_csv, filename: "category_evolution.csv" }
        format.xlsx { send_data generate_category_evolution_xlsx, filename: "category_evolution.xlsx" }
    end
  end

  def funding_concentration
    # Get companies with funding data and valid locations
    companies = Company.where(visible: true)
                      .where.not(location: [nil, "", "Location unknown"])
                      .where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
                            '2000',
                            Time.current.year.to_s,
                            '^\d{4}$')

    # Group companies by region
    regions = companies.group_by { |c| LocationRegionResolver.region_for_location(c.location) }
                      .transform_values(&:count)

    # Calculate funding metrics per region
    region_metrics = {}

    companies.group_by { |c| LocationRegionResolver.region_for_location(c.location) }.each do |region, companies_in_region|
        funded_companies = companies_in_region.reject { |c| c.total_funding_amount_usd.nil? || c.total_funding_amount_usd.zero? }
        total_funding = funded_companies.sum { |c| c.total_funding_amount_usd }
        company_count = companies_in_region.count
        funded_count = funded_companies.count

        region_metrics[region] = {
            company_count: company_count,
            funded_count: funded_count,
            total_funding: total_funding,
            avg_deal_size: funded_count > 0 ? total_funding / funded_count : 0
        }
    end

    # Calculate total funding for market share
    total_funding = region_metrics.values.sum { |v| v[:total_funding] }

    # Prepare data for view
    @table_data = region_metrics.map do |region, metrics|
        {
            region: region,
            company_count: metrics[:company_count],
            funded_count: metrics[:funded_count],
            total_funding: metrics[:total_funding],
            avg_deal_size: metrics[:avg_deal_size],
            market_share: total_funding > 0 ? (metrics[:total_funding] / total_funding.to_f * 100) : 0
        }
    end

    # Sort by total funding descending
    @table_data = @table_data.sort_by { |d| -d[:total_funding] }

    respond_to do |format|
        format.html
        format.csv { send_data generate_funding_concentration_csv, filename: "funding_concentration.csv" }
        format.xlsx { send_data generate_funding_concentration_xlsx, filename: "funding_concentration.xlsx" }
    end
  end

  def download_funding_concentration
    redirect_to statistics_funding_concentration_path(format: :csv)
  end

  def business_model
    redirect_to statistics_category_evolution_5_years_path(dimension: "revenue_model"), status: :moved_permanently
  end

  def target_client
    redirect_params = { dimension: "market_focus" }
    redirect_params[:view] = params[:view] if params[:view].present?
    redirect_to statistics_category_evolution_5_years_path(redirect_params), status: :moved_permanently
  end

  def country_distribution
    @geo_view = geo_view_param

    if @geo_view == "region"
      load_companies_by_region_data
    else
      load_country_distribution_data
    end

    respond_to do |format|
      format.html
      format.csv do
        if @geo_view == "region"
          send_data generate_region_country_csv, filename: "companies_by_region.csv", type: "text/csv; charset=utf-8", disposition: "attachment"
        else
          send_data generate_country_distribution_csv, filename: "country_distribution.csv", type: "text/csv; charset=utf-8", disposition: "attachment"
        end
      end
      format.xlsx do
        if @geo_view == "region"
          send_data generate_region_country_xlsx, filename: "companies_by_region.xlsx"
        else
          send_data generate_country_distribution_xlsx, filename: "country_distribution.xlsx"
        end
      end
      format.png { head :ok if @geo_view == "country" }
    end
  end

  def companies_by_region
    redirect_to statistics_country_distribution_path(params.permit(:view).merge(view: "region")), status: :moved_permanently
  end

  def funding_by_region
    redirect_to statistics_funding_by_category_path(dimension: "region"), status: :moved_permanently
  end

  def download_category_evolution
    send_data generate_csv(@table_data, ['Category', 'Total Companies', 'Growth Rate']),
             filename: "category_evolution_#{Time.current.strftime('%Y%m%d')}.csv"
  end

  def download_target_client
    redirect_params = { dimension: "market_focus", format: :csv }
    redirect_params[:view] = params[:view] if params[:view].present?
    redirect_to statistics_category_evolution_5_years_path(redirect_params), status: :moved_permanently
  end

  def download_business_model
    redirect_to statistics_category_evolution_5_years_path(dimension: "revenue_model", format: :csv), status: :moved_permanently
  end

  def venture_stage
    redirect_to statistics_funding_by_category_path(dimension: "venture_stage"), status: :moved_permanently
  end

  def download_venture_stage
    redirect_to statistics_funding_by_category_path(dimension: "venture_stage", format: :csv), status: :moved_permanently
  end

  def funding_stages
    redirect_to statistics_funding_by_category_path(dimension: "venture_stage"), status: :moved_permanently
  end

  def funding_efficiency
    cached = Rails.cache.fetch("statistics/funding_efficiency/#{company_cache_version}/#{category_cache_version}", expires_in: 10.minutes) do
      build_funding_efficiency_metrics
    end

    @category_metrics = cached[:category_metrics]
    @efficiency_scores = cached[:efficiency_scores]
    @funding_per_round = cached[:funding_per_round]
    @most_efficient = cached[:most_efficient]
    @highest_success = cached[:highest_success]
    @optimal_rounds = cached[:optimal_rounds]

    respond_to do |format|
      format.html
      format.csv do
        csv_data = CSV.generate do |csv|
          csv << ["Category", "Companies", "Funded Companies", "Total Funding", "Avg Funding",
                 "Avg Rounds", "Funding per Round", "Funding per Year", "Success Rate", "Efficiency Score"]
          @category_metrics.each do |category, metrics|
            csv << [
              category,
              metrics[:companies],
              metrics[:funded_companies],
              metrics[:total_funding],
              metrics[:avg_funding],
              metrics[:avg_rounds],
              metrics[:funding_per_round],
              metrics[:funding_per_year],
              metrics[:success_rate],
              metrics[:efficiency_score]
            ]
          end
        end
        send_data csv_data, filename: "funding_efficiency_analysis.csv"
      end
    end
  end

  def tag_distribution
    @tag_metrics = Rails.cache.fetch("statistics/tag_distribution/#{company_cache_version}", expires_in: 10.minutes) do
      build_tag_distribution_metrics
    end

    respond_to do |format|
      format.html
      format.csv do
        send_data generate_tag_distribution_csv,
                 filename: "tag_distribution_#{Time.current.strftime('%Y%m%d')}.csv"
      end
    end
  end

  def download_tag_distribution
    send_data generate_csv(@tag_metrics, ['Tag', 'Companies', 'Percentage', 'Average Funding']),
             filename: "tag_distribution_#{Time.current.strftime('%Y%m%d')}.csv"
  end

  def exit_patterns
    cached = Rails.cache.fetch("statistics/exit_patterns/#{company_cache_version}/#{category_cache_version}", expires_in: 10.minutes) do
      build_exit_pattern_metrics
    end

    @exit_metrics = cached[:exit_metrics]
    @exit_types = cached[:exit_types]
    @exit_timing = cached[:exit_timing]

    respond_to do |format|
      format.html
      format.csv do
        send_data generate_exit_patterns_csv,
                 filename: "exit_patterns_analysis_#{Time.current.strftime('%Y%m%d')}.csv"
      end
    end
  end

  def founders_journey
    @companies = Company.where(visible: true)
                       .where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
                             '2000',
                             Time.current.year.to_s,
                             '^\d{4}$')
                       .includes(:category)
                       .to_a  # Load into memory once

    # Initialize metrics
    @journey_metrics = {}
    total_companies = @companies.count.to_f

    # Define journey stages
    stages = ['Ideation', 'Early Growth', 'Scaling', 'Maturity']

    # Calculate metrics for each stage
    stages.each do |stage|
      companies_in_stage = case stage
      when 'Ideation'
        @companies.select { |c| c.founded_date.to_i >= (Time.current.year - 2) }
      when 'Early Growth'
        @companies.select { |c| (Time.current.year - 5..Time.current.year - 3).include?(c.founded_date.to_i) }
      when 'Scaling'
        @companies.select { |c| (Time.current.year - 8..Time.current.year - 6).include?(c.founded_date.to_i) }
      else # Maturity
        @companies.select { |c| c.founded_date.to_i < (Time.current.year - 8) }
      end

      # Calculate funding metrics
      total_funding = companies_in_stage.sum { |c| c.total_funding_amount_usd.to_f }
      avg_funding = companies_in_stage.any? ? (total_funding / companies_in_stage.size) : 0

      # Calculate success metrics
      successful = companies_in_stage.count { |c| ['Public', 'Acquired'].include?(self.class.stage_mapping[c.funding_status]) }
      success_rate = companies_in_stage.any? ? (successful.to_f / companies_in_stage.size * 100) : 0

      @journey_metrics[stage] = {
        count: companies_in_stage.size,
        percentage: (companies_in_stage.size / total_companies * 100).round(1),
        avg_funding: avg_funding,
        success_rate: success_rate
      }
    end

    # Calculate year-over-year progression
    @progression_data = {}
    (2000..Time.current.year).each do |year|
      companies_until_year = @companies.select { |c| c.founded_date.to_i <= year }

      # Skip years with no companies
      next if companies_until_year.empty?

      successful = companies_until_year.count { |c| ['Public', 'Acquired'].include?(self.class.stage_mapping[c.funding_status]) }
      total_funding = companies_until_year.sum { |c| c.total_funding_amount_usd.to_f }

      @progression_data[year] = {
        companies: companies_until_year.size,
        success_rate: (successful.to_f / companies_until_year.size * 100).round(1),
        avg_funding: companies_until_year.any? ? (total_funding / companies_until_year.size) : 0
      }
    end

    respond_to do |format|
      format.html
      format.csv do
        csv_data = CSV.generate do |csv|
          csv << ["Stage", "Companies", "Percentage", "Average Funding", "Success Rate"]
          @journey_metrics.each do |stage, metrics|
            csv << [
              stage,
              metrics[:count],
              metrics[:percentage],
              metrics[:avg_funding].round(2),
              metrics[:success_rate].round(1)
            ]
          end
        end
        send_data csv_data, filename: "founders_journey_analysis_#{Time.current.strftime('%Y%m%d')}.csv"
      end
    end
  end

  def download_funding_stages
    redirect_to statistics_funding_by_category_path(dimension: "venture_stage", format: :csv), status: :moved_permanently
  end

  def download_funding_efficiency
    send_data generate_csv(@category_metrics.map { |category, metrics|
      {
        category: category,
        companies: metrics[:companies],
        funded_companies: metrics[:funded_companies],
        total_funding: metrics[:total_funding],
        avg_funding: metrics[:avg_funding],
        avg_rounds: metrics[:avg_rounds],
        funding_per_round: metrics[:funding_per_round],
        funding_per_year: metrics[:funding_per_year],
        success_rate: metrics[:success_rate],
        efficiency_score: metrics[:efficiency_score]
      }
    }, ['Category', 'Companies', 'Funded Companies', 'Total Funding', 'Avg Funding',
        'Avg Rounds', 'Funding per Round', 'Funding per Year', 'Success Rate', 'Efficiency Score']),
    filename: "funding_efficiency_analysis_#{Time.current.strftime('%Y%m%d')}.csv"
  end

  def ai_trends
    @growth_view = growth_view_param
    @table_data = ai_trends_table_data

    respond_to do |format|
      format.html
      format.csv do
        send_data generate_ai_trends_csv(@table_data),
                  filename: "ai_trends_analysis_#{Time.current.strftime('%Y%m%d')}.csv",
                  type: "text/csv",
                  disposition: "attachment"
      end
    end
  end

  def download_ai_trends
    redirect_to statistics_ai_trends_path(format: :csv, view: params[:view])
  end

  def category_evolution_5_years
    load_industry_focus_data

    respond_to do |format|
      format.html
      format.csv do
        send_data industry_focus_csv_data,
                  filename: industry_focus_csv_filename,
                  type: "text/csv",
                  disposition: "attachment"
      end
    end
  end

  def download_category_evolution_5_years
    download_params = { format: :csv }
    dimension = industry_focus_dimension_param
    download_params[:dimension] = dimension if dimension != "industry"
    download_params[:view] = params[:view] if dimension == "market_focus" && params[:view].present?
    redirect_to statistics_category_evolution_5_years_path(download_params), status: :moved_permanently
  end

  def funding_by_category
    @funding_dimension = funding_dimension_param

    case @funding_dimension
    when "region"
      load_funding_by_region_data
    when "venture_stage"
      metrics = helpers.build_venture_stage_metrics
      @stage_metrics = metrics[:stage_metrics]
      @stage_data = metrics[:stage_data]
    else
      load_funding_by_category_data
    end

    respond_to do |format|
      format.html
      format.csv do
        if @funding_dimension == "venture_stage"
          csv_data = CSV.generate do |csv|
            csv << ["Venture Stage", "Companies", "Percentage"]
            @stage_metrics.each do |row|
              csv << [row[:stage], row[:count], row[:percentage]]
            end
          end
          send_data csv_data, filename: "venture_stage_analysis_#{Time.current.strftime('%Y%m%d')}.csv"
        elsif @funding_dimension == "region"
          send_data generate_region_country_csv, filename: "funding_by_region.csv", type: "text/csv; charset=utf-8", disposition: "attachment"
        else
          csv_data = CSV.generate do |csv|
            csv << ["Category", "Total Funding", "Company Count", "Average Funding", "Market Share (%)"]
            @table_data.each do |data|
              csv << [
                data[:category],
                data[:total_funding],
                data[:company_count],
                data[:avg_funding].round(2),
                data[:market_share].round(1)
              ]
            end
          end
          send_data csv_data,
                    filename: "funding_by_category_#{Time.current.strftime('%Y%m%d')}.csv",
                    type: "text/csv",
                    disposition: "attachment"
        end
      end
      format.xlsx do
        if @funding_dimension == "region"
          send_data generate_region_country_xlsx, filename: "funding_by_region.xlsx"
        elsif @funding_dimension != "venture_stage"
          p = Axlsx::Package.new
          wb = p.workbook
          wb.add_worksheet(name: "Funding by Category") do |sheet|
            sheet.add_row ["Category", "Total Funding", "Company Count", "Average Funding", "Market Share (%)"]
            @table_data.each do |data|
              sheet.add_row [
                data[:category],
                data[:total_funding],
                data[:company_count],
                data[:avg_funding].round(2),
                data[:market_share].round(1)
              ]
            end
          end
          send_data p.to_stream.read,
                    filename: "funding_by_category_#{Time.current.strftime('%Y%m%d')}.xlsx",
                    type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    disposition: "attachment"
        end
      end
    end
  end

  def download_funding_by_category
    download_params = { format: :csv }
    dimension = funding_dimension_param
    download_params[:dimension] = dimension if dimension != "category"
    redirect_to statistics_funding_by_category_path(download_params), status: :moved_permanently
  end

  private

  GROWTH_VIEWS = %w[cumulative annual].freeze
  GEO_VIEWS = %w[country region].freeze
  INDUSTRY_FOCUS_DIMENSIONS = %w[industry revenue_model market_focus].freeze
  FUNDING_DIMENSIONS = %w[category region venture_stage].freeze
  CATEGORY_EVOLUTION_CHART_COLORS = [
    "#8c1515", "#175e54", "#2986cc", "#8e5fa2", "#d55e00", "#37a4a6",
    "#5a865a", "#ae6a59", "#5b9bd5", "#6b6b8d", "#c67171", "#820000"
  ].freeze

  def growth_view_param
    params[:view].presence_in(GROWTH_VIEWS) || "cumulative"
  end

  def geo_view_param
    view = params[:view].to_s
    return "region" if view.in?(%w[region regions])

    "country"
  end

  def funding_view_param
    view = params[:view].to_s
    return "region" if view.in?(%w[region regions])

    "category"
  end

  def funding_dimension_param
    dimension = params[:dimension].presence_in(FUNDING_DIMENSIONS)
    return dimension if dimension

    funding_view_param == "region" ? "region" : "category"
  end

  def industry_focus_dimension_param
    params[:dimension].presence_in(INDUSTRY_FOCUS_DIMENSIONS) || "industry"
  end

  def load_industry_focus_data
    @focus_dimension = industry_focus_dimension_param
    @growth_view = growth_view_param

    case @focus_dimension
    when "revenue_model"
      metrics = build_revenue_model_metrics
      @model_metrics = metrics[:model_metrics]
      @model_data = metrics[:model_data]
    when "market_focus"
      metrics = build_target_client_yearly_metrics(annual: @growth_view == "annual")
      @chart_series = metrics[:table_data]
      @summary_data = metrics[:summary_data]
      @chart_colors = CATEGORY_EVOLUTION_CHART_COLORS.cycle.take(@chart_series.size).to_a
    else
      cached = Rails.cache.fetch(
        "statistics/category_evolution_5_years/#{company_cache_version}/#{category_cache_version}",
        expires_in: 10.minutes
      ) do
        build_category_evolution_yearly_metrics
      end

      @table_data = cached[:table_data]
      @summary_data = cached[:summary_data]
      @chart_series = @table_data
      @chart_colors = CATEGORY_EVOLUTION_CHART_COLORS.cycle.take(@chart_series.size).to_a
    end
  end

  def industry_focus_csv_data
    case @focus_dimension
    when "revenue_model"
      CSV.generate do |csv|
        csv << ["Revenue Model", "Companies", "Percentage", "Average Funding"]
        @model_metrics.each do |row|
          csv << [row[:model], row[:count], row[:percentage], row[:avg_funding].round(2)]
        end
      end
    when "market_focus"
      CSV.generate do |csv|
        csv << ["Target Client", "Companies", "Percentage", "Average Funding"]
        @summary_data.each do |row|
          csv << [row[:client], row[:total_companies], row[:percentage].round(1), row[:avg_funding].round(2)]
        end
      end
    else
      years = (@table_data.first&.dig(:yearly_data)&.keys || []).sort
      CSV.generate do |csv|
        csv << ["Category"] + years
        @table_data.each do |data|
          csv << [data[:category]] + years.map { |year| data[:yearly_data][year] || 0 }
        end
      end
    end
  end

  def industry_focus_csv_filename
    timestamp = Time.current.strftime("%Y%m%d")
    case @focus_dimension
    when "revenue_model"
      "business_model_analysis_#{timestamp}.csv"
    when "market_focus"
      "target_client_analysis_#{timestamp}.csv"
    else
      "category_evolution_#{timestamp}.csv"
    end
  end

  def load_country_distribution_data
    companies = located_companies_scope
    country_metrics = Hash.new { |hash, country| hash[country] = { companies: 0, total_funding: 0, funded_companies: 0 } }

    companies.each do |company|
      country = extract_country(company.location)
      next unless country

      country_metrics[country][:companies] += 1

      if company.total_funding_amount_usd && company.total_funding_amount_usd > 0
        country_metrics[country][:total_funding] += company.total_funding_amount_usd
        country_metrics[country][:funded_companies] += 1
      end
    end

    @chart_data = [["Country", "Companies"]]
    country_metrics.each do |country, metrics|
      @chart_data << [country, metrics[:companies]]
    end

    @table_data = country_metrics.map do |country, metrics|
      avg_funding = metrics[:funded_companies].positive? ? metrics[:total_funding] / metrics[:funded_companies] : 0

      {
        country: country,
        companies: metrics[:companies],
        total_funding: metrics[:total_funding],
        avg_funding: avg_funding
      }
    end.sort_by { |data| -data[:companies] }

    @top_countries = @table_data.take(3).map { |data| data[:country] }
    @top_funded_countries = @table_data.sort_by { |data| -data[:total_funding] }.take(3).map { |data| data[:country] }

    max_companies = country_metrics.values.map { |metrics| metrics[:companies] }.max || 0
    @geo_map_max = [((max_companies / 50.0).ceil * 50), 50].max
  end

  def load_companies_by_region_data
    region_country_metrics = build_region_country_metrics(located_companies_scope)
    @region_table_data = helpers.build_region_table_data(region_country_metrics)
    @region_sankey_data = helpers.region_country_sankey_data(region_country_metrics)
  end

  def maturity_base_scope
    Company.where(visible: true)
           .where("founded_date >= ? AND founded_date <= ? AND founded_date ~ ?",
                  "2000",
                  Time.current.year.to_s,
                  "^\d{4}$")
  end

  def build_funding_efficiency_metrics
    category_metrics = {}

    maturity_base_scope.joins(:category)
                       .group("categories.name")
                       .pluck(
                         Arel.sql("categories.name"),
                         Arel.sql("COUNT(*)"),
                         Arel.sql("COUNT(*) FILTER (WHERE total_funding_amount_usd > 0)"),
                         Arel.sql("COALESCE(SUM(total_funding_amount_usd) FILTER (WHERE total_funding_amount_usd > 0), 0)"),
                         Arel.sql("AVG(number_of_funding_rounds) FILTER (WHERE total_funding_amount_usd > 0)"),
                         Arel.sql("AVG(EXTRACT(YEAR FROM CURRENT_DATE) - NULLIF(founded_date, '')::integer) FILTER (WHERE total_funding_amount_usd > 0)"),
                         Arel.sql("COUNT(*) FILTER (WHERE total_funding_amount_usd > 10000000)")
                       ).each do |name, total, funded_count, total_funding, avg_rounds, avg_age, late_stage|
      funded_count = funded_count.to_i
      next if funded_count.zero?

      total = total.to_f
      total_funding = total_funding.to_f
      avg_rounds = avg_rounds.to_f
      avg_funding_per_company = total_funding / funded_count
      funding_per_round = avg_rounds.positive? ? avg_funding_per_company / avg_rounds : nil
      avg_age = avg_age.to_f
      funding_per_year = avg_age.positive? ? avg_funding_per_company / avg_age : nil
      success_rate = (late_stage.to_i / funded_count.to_f * 100)
      efficiency_score = calculate_efficiency_score(
        funding_per_round: funding_per_round,
        funding_per_year: funding_per_year,
        success_rate: success_rate,
        avg_rounds: avg_rounds
      )

      category_metrics[name] = {
        companies: total.to_i,
        funded_companies: funded_count,
        total_funding: total_funding,
        avg_funding: avg_funding_per_company,
        avg_rounds: avg_rounds.round(1),
        funding_per_round: funding_per_round&.round(2),
        funding_per_year: funding_per_year&.round(2),
        success_rate: success_rate.round(1),
        efficiency_score: efficiency_score
      }
    end

    category_metrics = category_metrics.sort_by { |_, metrics| -metrics[:efficiency_score] }.to_h
    {
      category_metrics: category_metrics,
      efficiency_scores: category_metrics.transform_values { |m| m[:efficiency_score] },
      funding_per_round: category_metrics.transform_values { |m| m[:funding_per_round] },
      most_efficient: category_metrics.first(3).map(&:first),
      highest_success: category_metrics.max_by { |_, m| m[:success_rate] }&.first,
      optimal_rounds: category_metrics.max_by { |_, m| m[:efficiency_score] }&.last&.dig(:avg_rounds)
    }
  end

  def build_category_evolution_yearly_metrics
    companies = Company.includes(:category)
                      .where(visible: true)
                      .where("founded_date >= ? AND founded_date <= ? AND founded_date ~ ?",
                             "2000",
                             Time.current.year.to_s,
                             FOUR_DIGIT_YEAR_REGEX)
                      .where.not(category_id: nil)

    start_year = 2000
    end_year = Time.current.year
    years = (start_year..end_year).map(&:to_s)

    categories = Category.where.not(name: "Unknown")
    category_data = {}

    categories.each do |category|
      category_data[category.id] = {
        category: category.name,
        yearly_data: years.index_with { 0 },
        total_companies: 0
      }
    end

    companies.each do |company|
      next if company.category.name == "Unknown"

      year = company.founded_date.to_i
      category_id = company.category_id

      (year..end_year).each do |y|
        category_data[category_id][:yearly_data][y.to_s] += 1
      end
      category_data[category_id][:total_companies] += 1
    end

    total_companies = category_data.values.sum { |d| d[:total_companies] }
    table_data = category_data.values.sort_by { |d| -d[:total_companies] }

    summary_data = table_data.map do |data|
      prev_year = (end_year - 1).to_s
      current_year = end_year.to_s
      growth_rate = if data[:yearly_data][prev_year].positive?
        ((data[:yearly_data][current_year] - data[:yearly_data][prev_year]) / data[:yearly_data][prev_year].to_f) * 100
      else
        0
      end

      {
        category: data[:category],
        total_companies: data[:total_companies],
        growth_rate: growth_rate,
        market_share: (data[:total_companies] / total_companies.to_f) * 100
      }
    end

    { table_data: table_data, summary_data: summary_data }
  end

  def build_revenue_model_metrics
    companies = stats_scoped_companies.includes(:business_models, :business_model).to_a
    model_counts = Hash.new(0)
    model_companies = Hash.new { |hash, key| hash[key] = [] }

    companies.each do |company|
      TaxonomyNormalizationService.canonical_revenue_model_names(company.revenue_model_names.join(", ")).each do |model_name|
        model_counts[model_name] += 1
        model_companies[model_name] << company
      end
    end

    total_companies = companies.size.to_f
    model_metrics = model_counts.map do |model_name, count|
      companies_for_model = model_companies[model_name]
      total_funding = companies_for_model.sum { |company| company.total_funding_amount_usd.to_f }
      avg_funding = companies_for_model.any? ? total_funding / companies_for_model.size : 0

      {
        model: model_name,
        count: count,
        percentage: total_companies.positive? ? (count / total_companies * 100).round(1) : 0,
        avg_funding: avg_funding
      }
    end.sort_by { |row| -row[:count] }

    {
      model_metrics: model_metrics,
      model_data: model_metrics.to_h { |row| [row[:model], row[:count]] }
    }
  end

  def stats_scoped_companies
    Company.where(visible: true)
           .where("founded_date >= ? AND founded_date <= ? AND founded_date ~ ?",
                  "2000",
                  Time.current.year.to_s,
                  FOUR_DIGIT_YEAR_REGEX)
  end

  def build_target_client_yearly_metrics(annual: false)
    companies = Company.where(visible: true)
                       .where("founded_date >= ? AND founded_date <= ? AND founded_date ~ ?",
                              "2000",
                              Time.current.year.to_s,
                              FOUR_DIGIT_YEAR_REGEX)
                       .includes(:target_client, :target_clients)
                       .to_a

    start_year = 2000
    end_year = Time.current.year
    years = (start_year..end_year).map(&:to_s)
    client_data = {}
    client_companies = Hash.new { |hash, key| hash[key] = [] }

    companies.each do |company|
      year = company.founded_date.to_i
      next unless year.between?(start_year, end_year)

      company.audience_names.each do |target|
        next if target.blank? || target == "Unknown"

        client_data[target] ||= { client: target, yearly_data: years.index_with { 0 }, total_companies: 0 }
        client_companies[target] << company

        if annual
          client_data[target][:yearly_data][year.to_s] += 1
        else
          (year..end_year).each do |y|
            client_data[target][:yearly_data][y.to_s] += 1
          end
        end

        client_data[target][:total_companies] += 1
      end
    end

    total_assignments = client_data.values.sum { |data| data[:total_companies] }
    table_data = client_data.values.sort_by { |data| -data[:total_companies] }

    summary_data = table_data.map do |data|
      prev_year = (end_year - 1).to_s
      current_year = end_year.to_s
      growth_rate = if data[:yearly_data][prev_year].to_i.positive?
                      ((data[:yearly_data][current_year].to_i - data[:yearly_data][prev_year].to_i) / data[:yearly_data][prev_year].to_f) * 100
                    else
                      0
                    end
      companies_for_client = client_companies[data[:client]]
      total_funding = companies_for_client.sum { |company| company.total_funding_amount_usd.to_f }
      avg_funding = companies_for_client.any? ? total_funding / companies_for_client.size : 0

      {
        client: data[:client],
        total_companies: data[:total_companies],
        percentage: total_assignments.positive? ? (data[:total_companies] / total_assignments.to_f * 100) : 0,
        growth_rate: growth_rate,
        avg_funding: avg_funding
      }
    end

    { table_data: table_data, summary_data: summary_data }
  end

  def ai_trends_table_data
    running_total = 0
    ai_company_counts_by_year.map do |year, new_companies|
      previous_total = running_total
      running_total += new_companies
      growth_rate = previous_total.positive? ? ((running_total - previous_total) / previous_total.to_f * 100) : 0

      {
        year: year,
        new_companies: new_companies,
        total_companies: running_total,
        growth_rate: growth_rate
      }
    end
  end

  def ai_company_counts_by_year
    ai_tags = TagNormalizationService.ai_related_tag_ids

    Company.joins(:taggings)
           .where(taggings: { tag_id: ai_tags })
           .where(visible: true)
           .where("founded_date ~ ?", FOUR_DIGIT_YEAR_REGEX)
           .group("CAST(founded_date AS INTEGER)")
           .count
           .select { |year, _| year >= 2010 }
           .sort_by { |year, _| year }
  end

  def generate_ai_trends_csv(table_data)
    CSV.generate do |csv|
      csv << ["Year", "New AI Companies", "Total AI Companies", "Growth Rate (%)"]
      table_data.each do |data|
        csv << [
          data[:year],
          data[:new_companies],
          data[:total_companies],
          data[:growth_rate].round(1)
        ]
      end
    end
  end

  def build_tag_distribution_metrics
    tags = Tag.joins(:companies)
              .where(companies: { visible: true })
              .select("MIN(tags.id) as id,
                       LOWER(REGEXP_REPLACE(tags.name, E'\\s+', ' ', 'g')) as normalized_name,
                       MIN(tags.name) as name,
                       COUNT(DISTINCT companies.id) as company_count")
              .group("LOWER(REGEXP_REPLACE(tags.name, E'\\s+', ' ', 'g'))")
              .having("COUNT(DISTINCT companies.id) > 8")
              .order(Arel.sql("COUNT(DISTINCT companies.id) DESC"))
              .limit(50)
              .to_a

    visible_count = Company.where(visible: true).count
    normalized_names = tags.map(&:normalized_name)
    avg_funding_by_tag = if normalized_names.any?
      Company.joins(:tags)
             .where(visible: true)
             .where.not(total_funding_amount_usd: [nil, 0])
             .where("LOWER(REGEXP_REPLACE(tags.name, E'\\s+', ' ', 'g')) IN (?)", normalized_names)
             .group(Arel.sql("LOWER(REGEXP_REPLACE(tags.name, E'\\s+', ' ', 'g'))"))
             .average(:total_funding_amount_usd)
    else
      {}
    end

    tags.map do |tag|
      {
        name: tag.name,
        count: tag.company_count,
        percentage: (tag.company_count.to_f / visible_count * 100).round(1),
        avg_funding: avg_funding_by_tag[tag.normalized_name].to_f
      }
    end
  end

  def build_exit_pattern_metrics
    companies = Company.where(visible: true).where.not(exit_date: nil).includes(:category).to_a
    category_totals = Company.group(:category_id).count
    categories_by_id = Category.all.index_by(&:id)
    exit_metrics = {}

    companies.group_by(&:category_id).each do |category_id, category_companies|
      category = categories_by_id[category_id]
      next unless category

      times_to_exit = category_companies.filter_map do |company|
        if company.founded_date.present? && company.exit_date.present?
          company.exit_date.year - company.founded_date.to_i
        end
      end
      next if times_to_exit.empty?

      category_total = category_totals[category_id].to_f
      exit_metrics[category.name] = {
        total_exits: category_companies.size,
        avg_time_to_exit: (times_to_exit.sum / times_to_exit.size.to_f).round(1),
        min_time_to_exit: times_to_exit.min,
        max_time_to_exit: times_to_exit.max,
        exit_rate: category_total.positive? ? (category_companies.size / category_total * 100).round(1) : 0
      }
    end

    {
      exit_metrics: exit_metrics.sort_by { |_, value| -value[:total_exits] }.to_h,
      exit_types: companies.group_by(&:status).transform_values(&:count),
      exit_timing: companies.group_by { |company| company.exit_date.year }.transform_values(&:count).sort.to_h
    }
  end

  def generate_tag_distribution_csv
    CSV.generate do |csv|
      csv << ["Tag", "Companies", "Percentage", "Average Funding"]
      @tag_metrics.each do |metric|
        csv << [metric[:name], metric[:count], metric[:percentage], metric[:avg_funding]]
      end
    end
  end

  FOUR_DIGIT_YEAR_REGEX = "^[0-9]{4}$"

  def visible_company_counts_by_year
    Rails.cache.fetch("statistics/visible_company_counts_by_year/#{company_cache_version}", expires_in: 10.minutes) do
      Company.where(visible: true)
             .where("founded_date ~ ?", "^\\d{4}$")
             .group(:founded_date)
             .count
             .transform_keys(&:to_i)
    end
  end

  def total_companies_table_data(start_year:, end_year:, counts_by_year: visible_company_counts_by_year)
    running_total = counts_by_year.sum { |year, count| year < start_year ? count : 0 }

    (start_year..end_year).map do |year|
      new_companies = counts_by_year.fetch(year, 0)
      previous_total = running_total
      running_total += new_companies
      growth_rate = previous_total.positive? ? ((running_total - previous_total) / previous_total.to_f * 100) : 0

      {
        year: year,
        total_companies: running_total,
        new_companies: new_companies,
        growth_rate: growth_rate
      }
    end
  end

  def calculate_growth_rate(year, count)
    previous_year = (year.to_i - 1).to_s
    previous_count = Company.where(visible: true)
                          .where(founded_date: previous_year)
                          .count

    previous_count > 0 ? ((count - previous_count) / previous_count.to_f * 100) : 0
  end

  def calculate_growth_rate_from_counts(year, count, counts_by_year)
    previous_count = counts_by_year.fetch(year.to_i - 1, 0)

    previous_count.positive? ? ((count - previous_count) / previous_count.to_f * 100) : 0
  end

  def calculate_avg_funding(companies)
    funded_companies = companies.where.not(total_funding_amount_usd: [nil, 0])
    return 0 if funded_companies.empty?
    funded_companies.average(:total_funding_amount_usd).to_f
  end

  def calculate_success_rate(companies)
    return 0 if companies.empty?
    successful = companies.count { |c| ['Public', 'Acquired'].include?(self.class.stage_mapping[c.funding_status]) }
    (successful / companies.count.to_f) * 100
  end

  def calculate_efficiency_score(metrics)
    return 0 unless metrics[:funding_per_round] && metrics[:funding_per_year] && metrics[:success_rate]

    # Normalize metrics to 0-25 range
    funding_round_score = [metrics[:funding_per_round] / 5_000_000, 1.0].min * 25  # Optimal ~$5M per round
    funding_year_score = [metrics[:funding_per_year] / 2_000_000, 1.0].min * 25    # Optimal ~$2M per year
    success_score = [metrics[:success_rate] / 100.0, 1.0].min * 25                 # Success rate percentage
    rounds_score = [(4.0 - (metrics[:avg_rounds] - 3).abs) / 4.0, 0.0].max * 25   # Optimal 2-4 rounds

    # Calculate total score (0-100)
    total_score = (funding_round_score + funding_year_score + success_score + rounds_score).round(1)
    [total_score, 100.0].min  # Cap at 100
  end

  def generate_exit_patterns_csv
    CSV.generate do |csv|
      csv << ['Category', 'Total Exits', 'Avg Time to Exit', 'Min Time', 'Max Time', 'Exit Rate']
      @exit_metrics.each do |category, metrics|
        csv << [
          category,
          metrics[:total_exits],
          metrics[:avg_time_to_exit],
          metrics[:min_time_to_exit],
          metrics[:max_time_to_exit],
          metrics[:exit_rate]
        ]
      end
    end
  end

  def generate_csv(data, headers)
    CSV.generate do |csv|
      csv << headers
      data.each do |row|
        csv << headers.map { |h| row[h.downcase.gsub(' ', '_').to_sym] }
      end
    end
  end

  def generate_category_evolution_csv
    CSV.generate do |csv|
        csv << ['Category', 'Total Companies', 'Growth Rate', 'Market Share']
        @summary_data.each do |data|
            csv << [
                data[:category],
                data[:total_companies],
                "#{data[:growth_rate].round(1)}%",
                "#{data[:market_share].round(1)}%"
            ]
        end
    end
  end

  def generate_funding_concentration_csv
    CSV.generate do |csv|
        csv << ['Region', 'Total Companies', 'Funded Companies', 'Total Funding', 'Avg Deal Size', 'Market Share']
        @table_data.each do |data|
            csv << [
                data[:region],
                data[:company_count],
                data[:funded_count],
                data[:total_funding],
                data[:avg_deal_size],
                "#{data[:market_share].round(1)}%"
            ]
        end
    end
  end

  def generate_category_evolution_xlsx
    Axlsx::Package.new do |p|
        p.workbook.add_worksheet(name: 'Category Evolution') do |sheet|
            sheet.add_row ['Category', 'Total Companies', 'Growth Rate', 'Market Share']
            @summary_data.each do |data|
                sheet.add_row [
                    data[:category],
                    data[:total_companies],
                    "#{data[:growth_rate].round(1)}%",
                    "#{data[:market_share].round(1)}%"
                ]
            end
        end
    end.to_stream.read
  end

  def generate_funding_concentration_xlsx
    Axlsx::Package.new do |p|
        p.workbook.add_worksheet(name: 'Funding Concentration') do |sheet|
            sheet.add_row ['Region', 'Total Companies', 'Funded Companies', 'Total Funding', 'Avg Deal Size', 'Market Share']
            @table_data.each do |data|
                sheet.add_row [
                    data[:region],
                    data[:company_count],
                    data[:funded_count],
                    data[:total_funding],
                    data[:avg_deal_size],
                    "#{data[:market_share].round(1)}%"
                ]
            end
        end
    end.to_stream.read
  end

  def generate_companies_founded_csv
    CSV.generate do |csv|
        csv << ['Year', 'New Companies', 'Total Companies', 'Growth Rate']
        @table_data.each do |data|
            csv << [
                data[:year],
                data[:new_companies],
                data[:total_companies],
                "#{data[:growth_rate].round(1)}%"
            ]
        end
    end
  end

  def generate_companies_founded_xlsx
    Axlsx::Package.new do |p|
        p.workbook.add_worksheet(name: 'Companies Founded') do |sheet|
            sheet.add_row ['Year', 'New Companies', 'Total Companies', 'Growth Rate']
            @table_data.each do |data|
                sheet.add_row [
                    data[:year],
                    data[:new_companies],
                    data[:total_companies],
                    "#{data[:growth_rate].round(1)}%"
                ]
            end
        end
    end.to_stream.read
  end

  def extract_country(location)
    ::LocationCountryResolver.country_name_for(location)
  end

  def normalize_country_name(country)
    ::LocationCountryResolver.normalize_country_name(country)
  end

  def load_funding_by_category_data
    companies = funded_companies_scope.includes(:category)

    funding_by_category = {}

    companies.group_by { |c| c.category&.name || "Unknown" }.each do |category, companies_in_category|
      total_funding = companies_in_category.sum(&:total_funding_amount_usd)
      company_count = companies_in_category.count

      funding_by_category[category] = {
        total_funding: total_funding,
        company_count: company_count,
        avg_funding: company_count > 0 ? total_funding / company_count : 0
      }
    end

    total_funding = funding_by_category.sum { |_, v| v[:total_funding] }

    @table_data = funding_by_category.map do |category, metrics|
      {
        category: category,
        total_funding: metrics[:total_funding],
        company_count: metrics[:company_count],
        avg_funding: metrics[:avg_funding],
        market_share: total_funding > 0 ? metrics[:total_funding] / total_funding * 100 : 0
      }
    end.sort_by { |item| -item[:total_funding] }

    @chart_data = {
      name: "Total Funding",
      data: @table_data.first(10).map { |d| [d[:category], d[:total_funding]] }
    }
  end

  def load_funding_by_region_data
    region_country_metrics = build_region_country_metrics(funded_companies_scope)
    @region_table_data = helpers.build_funding_region_table_data(region_country_metrics)
    @region_sankey_data = helpers.region_country_sankey_data(
      region_country_metrics,
      root: StatisticsHelper::REGION_COUNTRY_FUNDING_ROOT,
      value_key: :total_funding
    )
  end

  def funded_companies_scope
    located_companies_scope.where.not(total_funding_amount_usd: [nil, 0])
  end

  def located_companies_scope
    Company.where(visible: true)
           .where.not(location: [nil, "", "Location unknown"])
           .where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
                  '2000',
                  Time.current.year.to_s,
                  FOUR_DIGIT_YEAR_REGEX)
  end

  def build_region_country_metrics(companies)
    region_country_metrics = Hash.new { |regions, region| regions[region] = Hash.new { |countries, country| countries[country] = { companies: 0, total_funding: 0, funded_companies: 0 } } }

    companies.each do |company|
        country = extract_country(company.location)
        next unless country

        region = LocationRegionResolver.region_for_country(country)
        region_country_metrics[region][country][:companies] += 1

        if company.total_funding_amount_usd && company.total_funding_amount_usd > 0
            region_country_metrics[region][country][:total_funding] += company.total_funding_amount_usd
            region_country_metrics[region][country][:funded_companies] += 1
        end
    end

    region_country_metrics
  end

  def generate_region_country_csv
    CSV.generate do |csv|
        csv << ['Region', 'Country', 'Companies', 'Total Funding', 'Avg Funding']
        @region_table_data.each do |region_data|
            if region_data[:country_label].present?
                csv << [
                    region_data[:region],
                    region_data[:country_label],
                    region_data[:companies],
                    region_data[:total_funding],
                    region_data[:avg_funding]
                ]
            else
                region_data[:countries].each do |country_data|
                    csv << [
                        region_data[:region],
                        country_data[:country],
                        country_data[:companies],
                        country_data[:total_funding],
                        country_data[:avg_funding]
                    ]
                end
            end
        end
    end
  end

  def generate_region_country_xlsx
    Axlsx::Package.new do |package|
        package.workbook.add_worksheet(name: 'Companies by Region') do |sheet|
            sheet.add_row ['Region', 'Country', 'Companies', 'Total Funding', 'Avg Funding']
            @region_table_data.each do |region_data|
                if region_data[:country_label].present?
                    sheet.add_row [
                        region_data[:region],
                        region_data[:country_label],
                        region_data[:companies],
                        region_data[:total_funding],
                        region_data[:avg_funding]
                    ]
                else
                    region_data[:countries].each do |country_data|
                        sheet.add_row [
                            region_data[:region],
                            country_data[:country],
                            country_data[:companies],
                            country_data[:total_funding],
                            country_data[:avg_funding]
                        ]
                    end
                end
            end
        end
    end.to_stream.read
  end

  def generate_country_distribution_csv
    CSV.generate do |csv|
        csv << ['Country', 'Companies', 'Total Funding', 'Avg Funding']
        @table_data.each do |data|
            csv << [
                data[:country],
                data[:companies],
                data[:total_funding],
                data[:avg_funding]
            ]
        end
    end
  end

  def generate_country_distribution_xlsx
    Axlsx::Package.new do |p|
        p.workbook.add_worksheet(name: 'Country Distribution') do |sheet|
            sheet.add_row ['Country', 'Companies', 'Total Funding', 'Avg Funding']
            @table_data.each do |data|
                sheet.add_row [
                    data[:country],
                    data[:companies],
                    data[:total_funding],
                    data[:avg_funding]
                ]
            end
        end
    end.to_stream.read
  end
end
