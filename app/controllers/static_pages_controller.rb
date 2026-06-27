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
    @home_category_counts = Rails.cache.fetch("home/visible_category_counts/#{Company.maximum(:updated_at)&.to_i}/#{Category.maximum(:updated_at)&.to_i}", expires_in: 10.minutes) do
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

  def total_companies
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
    counts_by_year = visible_company_counts_by_year
    earliest_year = [counts_by_year.keys.min || 1975, 1975].max
    @table_data = total_companies_table_data(start_year: earliest_year, end_year: Time.current.year, counts_by_year: counts_by_year)

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
                  filename: "total_companies_all_time.csv",
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
                  filename: "total_companies_all_time.xlsx",
                  type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                  disposition: 'attachment'
      end
    end
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
      format.html
      format.csv { send_data generate_companies_founded_csv, filename: "companies_founded.csv" }
      format.xlsx { send_data generate_companies_founded_xlsx, filename: "companies_founded.xlsx" }
    end
  end

  def download_companies_founded
    redirect_to statistics_companies_founded_path(format: :csv)
  end

  def category_evolution
    cache_key = "statistics/category_evolution/#{Company.maximum(:updated_at)&.to_i}/#{Category.maximum(:updated_at)&.to_i}"
    if (cached_data = Rails.cache.read(cache_key))
      @table_data = cached_data[:table_data]
      @summary_data = cached_data[:summary_data]
    else
    # Get all companies with their categories and founding years
    companies = Company.includes(:category)
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
    regions = companies.group_by { |c| extract_region(c.location) }
                      .transform_values(&:count)

    # Calculate funding metrics per region
    region_metrics = {}

    companies.group_by { |c| extract_region(c.location) }.each do |region, companies_in_region|
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

  def category_success
    @companies = Company.where(visible: true)
                       .where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
                             '2000',
                             (Time.current.year - 5).to_s, # Exclude last 5 years
                             '^\d{4}$')
                       .includes(:category)

    # Calculate success metrics by category
    categories = Category.where.not(name: 'Unknown')
                        .joins(:companies)
                        .group('categories.id')
                        .having('COUNT(companies.id) > 5')

    @success_metrics = categories.map do |category|
      cat_companies = @companies.select { |c| c.category == category }
      total = cat_companies.count.to_f

      # Calculate metrics
      survival_rate = calculate_survival_rate(cat_companies)
      funding_success = calculate_funding_success(cat_companies)
      exit_rate = calculate_exit_rate(cat_companies)

      {
        name: category.name,
        survival_rate: survival_rate,
        funding_success: funding_success,
        exit_rate: exit_rate
      }
    end.sort_by { |d| -d[:survival_rate] }

    # Prepare data for chart
    @survival_data = @success_metrics.map { |d| [d[:name], d[:survival_rate]] }

    # Calculate top performers for research notes
    @top_survival = @success_metrics.take(3).map { |d| d[:name] }
    @top_funding_success = @success_metrics.sort_by { |d| -d[:funding_success] }
                                         .take(3)
                                         .map { |d| d[:name] }
    @top_exits = @success_metrics.sort_by { |d| -d[:exit_rate] }
                                .take(3)
                                .map { |d| d[:name] }
  end

  def business_model
    # Get all visible companies
    @companies = Company.where(visible: true)
                       .where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
                             '2000',
                             Time.current.year.to_s,
                             '^\d{4}$')
                       .includes(:business_model)

    # Prepare data for the business model distribution chart
    models = @companies.group(:business_model_id).count
    @model_data = {}
    models.each do |model_id, count|
      model_name = model_id ? BusinessModel.find(model_id).name : 'Unknown'
      @model_data[model_name] = count
    end

    # Calculate business model success metrics
    @model_metrics = models.map do |model_id, count|
      model = model_id ? BusinessModel.find(model_id) : nil
      model_name = model ? model.name : 'Unknown'
      companies = @companies.where(business_model_id: model_id)

      {
        model: model_name,
        count: count,
        percentage: (count.to_f / @companies.count * 100).round(1),
        avg_funding: calculate_avg_funding(companies),
        success_rate: calculate_success_rate(companies)
      }
    end
  end

  def target_client
    @companies = Company.where(visible: true)
                       .where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
                             '2000',
                             Time.current.year.to_s,
                             '^\d{4}$')
                       .includes(:target_client)
                       .to_a  # Load into memory once

    # Initialize counters for individual target clients
    individual_counts = Hash.new(0)
    client_companies = Hash.new { |h, k| h[k] = [] }

    # Count each target client individually
    @companies.each do |company|
      if company.target_client&.name
        # Split multiple targets and count each one
        targets = company.target_client.name.split(/,\s*/)
        targets.each do |target|
          individual_counts[target] += 1
          client_companies[target] << company
        end
      end
    end

    # Calculate total for percentages
    total_companies = @companies.count.to_f

    # Prepare metrics
    @client_metrics = []
    @client_data = {}

    # Process each individual target client
    individual_counts.each do |client_name, count|
      next if count < 10  # Skip very small segments

      # Calculate average funding for companies targeting this client
      companies_for_client = client_companies[client_name]
      total_funding = companies_for_client.sum { |c| c.total_funding_amount_usd.to_f }
      avg_funding = companies_for_client.any? ? (total_funding / companies_for_client.size) : 0

      metrics = {
        client: client_name,
        count: count,
        percentage: (count.to_f / total_companies * 100).round(1),
        avg_funding: avg_funding
      }

      @client_metrics << metrics
      @client_data[client_name] = count
    end

    # Sort by count descending
    @client_metrics.sort_by! { |m| -m[:count] }
    @client_data = @client_data.sort_by { |_, count| -count }.to_h

    respond_to do |format|
      format.html
      format.csv do
        csv_data = CSV.generate do |csv|
          csv << ["Target Client", "Companies", "Percentage", "Average Funding"]
          @client_metrics.each do |metrics|
            csv << [
              metrics[:client],
              metrics[:count],
              metrics[:percentage],
              metrics[:avg_funding].round(2)
            ]
          end
        end
        send_data csv_data, filename: "target_client_analysis_#{Time.current.strftime('%Y%m%d')}.csv"
      end
    end
  end

  def country_distribution
    # Get companies with valid locations
    companies = Company.where(visible: true)
                      .where.not(location: [nil, "", "Location unknown"])
                      .where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
                            '2000',
                            Time.current.year.to_s,
                            '^\d{4}$')

    # Group companies by country and calculate metrics
    country_metrics = {}

    companies.each do |company|
        country = extract_country(company.location)
        next unless country

        country_metrics[country] ||= {
            companies: 0,
            total_funding: 0,
            funded_companies: 0
        }

        country_metrics[country][:companies] += 1

        if company.total_funding_amount_usd && company.total_funding_amount_usd > 0
            country_metrics[country][:total_funding] += company.total_funding_amount_usd
            country_metrics[country][:funded_companies] += 1
        end
    end

    # Prepare data for view
    @chart_data = []
    @chart_data << ['Country', 'Companies']  # Header row
    country_metrics.each do |country, metrics|
        @chart_data << [country, metrics[:companies]]
    end

    # Prepare table data
    @table_data = country_metrics.map do |country, metrics|
        avg_funding = metrics[:funded_companies] > 0 ?
                     metrics[:total_funding] / metrics[:funded_companies] :
                     0

        {
            country: country,
            companies: metrics[:companies],
            total_funding: metrics[:total_funding],
            avg_funding: avg_funding
        }
    end

    # Sort table data by number of companies
    @table_data.sort_by! { |d| -d[:companies] }

    # Get top countries for research notes
    @top_countries = @table_data.take(3).map { |d| d[:country] }
    @top_funded_countries = @table_data.sort_by { |d| -d[:total_funding] }.take(3).map { |d| d[:country] }

    respond_to do |format|
        format.html
        format.csv { send_data generate_country_distribution_csv, filename: "country_distribution.csv", type: "text/csv; charset=utf-8", disposition: "attachment" }
        format.xlsx { send_data generate_country_distribution_xlsx, filename: "country_distribution.xlsx" }
        format.png { head :ok } # Just return a success status for PNG downloads (handled by JavaScript)
    end
  end

  def download_category_evolution
    send_data generate_csv(@table_data, ['Category', 'Total Companies', 'Growth Rate']),
             filename: "category_evolution_#{Time.current.strftime('%Y%m%d')}.csv"
  end

  def download_category_success
    send_data generate_csv(@success_metrics, ['Category', 'Survival Rate', 'Funding Success', 'Exit Rate']),
             filename: "category_success_#{Time.current.strftime('%Y%m%d')}.csv"
  end

  def download_business_model
    send_data generate_csv(@model_metrics, ['Business Model', 'Companies', 'Percentage', 'Avg Funding']),
             filename: "business_model_#{Time.current.strftime('%Y%m%d')}.csv"
  end

  def download_target_client
    send_data generate_csv(@client_metrics, ['Target Client', 'Companies', 'Percentage', 'Average Funding']),
             filename: "target_client_analysis_#{Time.current.strftime('%Y%m%d')}.csv"
  end

  def funding_stages
    @companies = Company.where(visible: true)
                       .where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
                             '2000',
                             Time.current.year.to_s,
                             '^\d{4}$')

    # Define funding stages and their thresholds
    funding_stages = {
      'Pre-seed' => 500_000,
      'Seed' => 2_000_000,
      'Series A' => 10_000_000,
      'Series B' => 30_000_000,
      'Series C+' => Float::INFINITY
    }

    # Initialize data structures
    @stage_data = {}
    @progression_data = {}
    total_companies = @companies.count.to_f

    # Calculate companies in each stage
    @companies.each do |company|
      funding = company.total_funding_amount_usd.to_f
      stage = funding_stages.find { |_, threshold| funding <= threshold }&.first || 'Series C+'
      @stage_data[stage] ||= { count: 0, total_funding: 0 }
      @stage_data[stage][:count] += 1
      @stage_data[stage][:total_funding] += funding
    end

    # Calculate percentages and average funding
    @stage_data.each do |stage, data|
      data[:percentage] = (data[:count] / total_companies * 100).round(1)
      data[:avg_funding] = data[:count] > 0 ? (data[:total_funding] / data[:count]).round(2) : 0
    end

    # Sort stages by funding amount
    @stage_data = @stage_data.sort_by { |stage, _| funding_stages.keys.index(stage) }.to_h

    # Calculate progression metrics
    progression_counts = {
      'Pre-seed to Seed' => 0,
      'Seed to Series A' => 0,
      'Series A to B' => 0,
      'Series B to C+' => 0
    }

    # Count companies that have progressed through stages
    @companies.each do |company|
      rounds = company.number_of_funding_rounds.to_i
      funding = company.total_funding_amount_usd.to_f

      if rounds >= 2 && funding > funding_stages['Pre-seed']
        progression_counts['Pre-seed to Seed'] += 1
      end
      if rounds >= 3 && funding > funding_stages['Seed']
        progression_counts['Seed to Series A'] += 1
      end
      if rounds >= 4 && funding > funding_stages['Series A']
        progression_counts['Series A to B'] += 1
      end
      if rounds >= 5 && funding > funding_stages['Series B']
        progression_counts['Series B to C+'] += 1
      end
    end

    # Calculate success rates
    @progression_rates = progression_counts.transform_values do |count|
      (count / total_companies * 100).round(1)
    end

    # Get top performing categories in late stages
    @top_categories = Category.joins(:companies)
                            .where(companies: { id: @companies.where('total_funding_amount_usd > ?', funding_stages['Series A']) })
                            .group('categories.id', 'categories.name')
                            .order('COUNT(companies.id) DESC')
                            .limit(3)
                            .pluck('categories.name')

    respond_to do |format|
      format.html
      format.csv do
        csv_data = CSV.generate do |csv|
          csv << ["Stage", "Companies", "Percentage", "Total Funding", "Average Funding"]
          @stage_data.each do |stage, data|
            csv << [
              stage,
              data[:count],
              data[:percentage],
              data[:total_funding],
              data[:avg_funding]
            ]
          end
          csv << []
          csv << ["Progression", "Success Rate"]
          @progression_rates.each do |progression, rate|
            csv << [progression, rate]
          end
        end
        send_data csv_data, filename: "funding_stages_analysis.csv"
      end
    end
  end

  def category_maturity
    @companies = Company.where(visible: true)
                       .where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
                             '2000',
                             Time.current.year.to_s,
                             '^\d{4}$')
                       .includes(:category)

    # Calculate maturity metrics for each category
    category_metrics = {}

    Category.all.each do |category|
      category_companies = @companies.where(category: category)
      next if category_companies.empty?

      # Calculate various maturity indicators
      total_companies = category_companies.count.to_f
      avg_age = category_companies.average("EXTRACT(YEAR FROM CURRENT_DATE) - founded_date::integer")
      total_funding = category_companies.sum(:total_funding_amount_usd)
      avg_funding = total_funding / total_companies
      funded_companies = category_companies.where('total_funding_amount_usd > 0').count
      funding_rate = (funded_companies / total_companies * 100)
      late_stage_companies = category_companies.where('total_funding_amount_usd > ?', 10_000_000).count
      late_stage_rate = (late_stage_companies / total_companies * 100)

      # Calculate maturity score (0-100)
      maturity_score = calculate_maturity_score(
        total_companies: total_companies,
        avg_age: avg_age,
        avg_funding: avg_funding,
        funding_rate: funding_rate,
        late_stage_rate: late_stage_rate
      )

      # Determine maturity stage
      maturity_stage = case maturity_score
                      when 0..25 then 'Emerging'
                      when 26..50 then 'Growing'
                      when 51..75 then 'Established'
                      else 'Mature'
                      end

      category_metrics[category.name] = {
        companies: total_companies.to_i,
        avg_age: avg_age&.round(1) || 0,
        total_funding: total_funding,
        avg_funding: avg_funding,
        funding_rate: funding_rate.round(1),
        late_stage_rate: late_stage_rate.round(1),
        maturity_score: maturity_score,
        maturity_stage: maturity_stage
      }
    end

    # Sort by maturity score
    @category_metrics = category_metrics.sort_by { |_, metrics| -metrics[:maturity_score] }.to_h

    # Prepare chart data
    @chart_data = @category_metrics.transform_values { |m| m[:maturity_score] }

    # Get insights for research notes
    @mature_categories = @category_metrics.select { |_, m| m[:maturity_stage] == 'Mature' }.keys
    @emerging_categories = @category_metrics.select { |_, m| m[:maturity_stage] == 'Emerging' }.keys
    @highest_growth = @category_metrics.max_by { |_, m| m[:funding_rate] }&.first

    respond_to do |format|
      format.html
      format.csv do
        csv_data = CSV.generate do |csv|
          csv << ["Category", "Companies", "Avg Age", "Total Funding", "Avg Funding", "Funding Rate", "Late Stage Rate", "Maturity Score", "Stage"]
          @category_metrics.each do |category, metrics|
            csv << [
              category,
              metrics[:companies],
              metrics[:avg_age],
              metrics[:total_funding],
              metrics[:avg_funding],
              metrics[:funding_rate],
              metrics[:late_stage_rate],
              metrics[:maturity_score],
              metrics[:maturity_stage]
            ]
          end
        end
        send_data csv_data, filename: "category_maturity_analysis.csv"
      end
    end
  end

  def funding_efficiency
    @companies = Company.where(visible: true)
                       .where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
                             '2000',
                             Time.current.year.to_s,
                             '^\d{4}$')
                       .includes(:category)

    # Calculate efficiency metrics by category
    category_metrics = {}

    Category.all.each do |category|
      category_companies = @companies.where(category: category)
      next if category_companies.empty?

      funded_companies = category_companies.where('total_funding_amount_usd > 0')
      next if funded_companies.empty?

      total_companies = category_companies.count.to_f
      total_funding = funded_companies.sum(:total_funding_amount_usd)
      avg_funding_per_company = total_funding / funded_companies.count
      avg_rounds = funded_companies.average(:number_of_funding_rounds).to_f
      funding_per_round = avg_funding_per_company / avg_rounds if avg_rounds > 0

      # Calculate time-based metrics
      avg_age = funded_companies.average("EXTRACT(YEAR FROM CURRENT_DATE) - founded_date::integer")
      funding_per_year = avg_funding_per_company / avg_age if avg_age > 0

      # Calculate success metrics
      late_stage = funded_companies.where('total_funding_amount_usd > ?', 10_000_000).count
      success_rate = (late_stage / funded_companies.count.to_f * 100)

      # Calculate efficiency score (0-100)
      efficiency_score = calculate_efficiency_score(
        funding_per_round: funding_per_round,
        funding_per_year: funding_per_year,
        success_rate: success_rate,
        avg_rounds: avg_rounds
      )

      category_metrics[category.name] = {
        companies: total_companies.to_i,
        funded_companies: funded_companies.count,
        total_funding: total_funding,
        avg_funding: avg_funding_per_company,
        avg_rounds: avg_rounds.round(1),
        funding_per_round: funding_per_round&.round(2),
        funding_per_year: funding_per_year&.round(2),
        success_rate: success_rate.round(1),
        efficiency_score: efficiency_score
      }
    end

    # Sort by efficiency score
    @category_metrics = category_metrics.sort_by { |_, metrics| -metrics[:efficiency_score] }.to_h

    # Prepare chart data
    @efficiency_scores = @category_metrics.transform_values { |m| m[:efficiency_score] }
    @funding_per_round = @category_metrics.transform_values { |m| m[:funding_per_round] }

    # Get insights for research notes
    @most_efficient = @category_metrics.first(3).map(&:first)
    @highest_success = @category_metrics.max_by { |_, m| m[:success_rate] }&.first
    @optimal_rounds = @category_metrics.max_by { |_, m| m[:efficiency_score] }&.last[:avg_rounds]

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
    # Get unique tag data with company counts, properly deduplicating by normalized name
    @tags = Tag.joins(:companies)
             .where(companies: { visible: true })
             .select("MIN(tags.id) as id,
                     LOWER(REGEXP_REPLACE(tags.name, E'\\s+', ' ', 'g')) as normalized_name,
                     MIN(tags.name) as name,
                     COUNT(DISTINCT companies.id) as company_count")
             .group("LOWER(REGEXP_REPLACE(tags.name, E'\\s+', ' ', 'g'))")
             .having('COUNT(DISTINCT companies.id) > 8')
             .order(Arel.sql('COUNT(DISTINCT companies.id) DESC'))
             .limit(50)

    # Prepare data for tag cloud and table
    @tag_metrics = @tags.map do |tag|
      {
        name: tag.name,
        count: tag.company_count,
        percentage: (tag.company_count.to_f / Company.where(visible: true).count * 100).round(1),
        avg_funding: calculate_avg_funding(Tag.where("LOWER(REGEXP_REPLACE(name, E'\\s+', ' ', 'g')) = ?", tag.normalized_name).first.companies.where(visible: true))
      }
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

  def innovation_hubs
    @companies = Company.where(visible: true)
                       .where.not(location: [nil, "", "Location unknown"])
                       .includes(:tags, :category)

    # Group companies by region and analyze technology patterns
    @region_metrics = {}

    @companies.group_by { |c| extract_region(c.location) }.each do |region, companies|
      # Calculate technology concentration
      tech_tags = companies.flat_map { |c| c.tags.map(&:name) }
      tag_counts = tech_tags.tally
      total_tags = tag_counts.values.sum.to_f

      # Calculate top technologies
      top_techs = tag_counts.sort_by { |_, count| -count }.first(5)

      # Calculate innovation diversity index (normalized Shannon index)
      diversity_index = if total_tags > 0
        h = tag_counts.values.sum { |count| p = count / total_tags; -p * Math.log(p) }
        h / Math.log(tag_counts.size) # Normalize to 0-1
      else
        0
      end

      # Calculate year-over-year growth
      yearly_companies = companies.group_by { |c| c.founded_date.to_i }
      current_year = Time.current.year
      yoy_growth = if yearly_companies[current_year - 1].to_a.size > 0
        ((yearly_companies[current_year].to_a.size - yearly_companies[current_year - 1].to_a.size) /
         yearly_companies[current_year - 1].to_a.size.to_f * 100).round(1)
      else
        0
      end

      @region_metrics[region] = {
        companies: companies.size,
        top_technologies: top_techs,
        diversity_index: (diversity_index * 100).round(1),
        yoy_growth: yoy_growth,
        specialization: calculate_specialization_score(companies)
      }
    end

    # Sort regions by number of companies
    @region_metrics = @region_metrics.sort_by { |_, v| -v[:companies] }.to_h

    # Prepare chart data
    @tech_concentration = @region_metrics.transform_values { |v| v[:companies] }
    @diversity_scores = @region_metrics.transform_values { |v| v[:diversity_index] }
    @growth_rates = @region_metrics.transform_values { |v| v[:yoy_growth] }

    respond_to do |format|
      format.html
      format.csv do
        send_data generate_innovation_hubs_csv,
                 filename: "innovation_hubs_analysis_#{Time.current.strftime('%Y%m%d')}.csv"
      end
    end
  end

  def exit_patterns
    @companies = Company.where(visible: true)
                       .where.not(exit_date: nil)
                       .includes(:category)

    # Calculate time to exit statistics
    @exit_metrics = {}

    Category.all.each do |category|
      category_companies = @companies.select { |c| c.category_id == category.id }
      next if category_companies.empty?

      times_to_exit = category_companies.map do |company|
        if company.founded_date.present? && company.exit_date.present?
          company.exit_date.year - company.founded_date.to_i
        end
      end.compact

      next if times_to_exit.empty?

      @exit_metrics[category.name] = {
        total_exits: category_companies.size,
        avg_time_to_exit: (times_to_exit.sum / times_to_exit.size.to_f).round(1),
        min_time_to_exit: times_to_exit.min,
        max_time_to_exit: times_to_exit.max,
        exit_rate: (category_companies.size / Company.where(category: category).count.to_f * 100).round(1)
      }
    end

    # Sort by total exits
    @exit_metrics = @exit_metrics.sort_by { |_, v| -v[:total_exits] }.to_h

    # Calculate exit type distribution
    @exit_types = @companies.group_by(&:status).transform_values(&:count)

    # Calculate exit timing patterns
    @exit_timing = @companies.group_by { |c| c.exit_date.year }
                            .transform_values(&:count)
                            .sort.to_h

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
    send_data generate_csv(@stage_data.map { |stage, data|
      {
        stage: stage,
        companies: data[:count],
        percentage: data[:percentage],
        total_funding: data[:total_funding],
        avg_funding: data[:avg_funding]
      }
    }, ['Stage', 'Companies', 'Percentage', 'Total Funding', 'Average Funding']),
    filename: "funding_stages_analysis_#{Time.current.strftime('%Y%m%d')}.csv"
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
    ai_tags = Tag.where("LOWER(name) IN (?)", ['ai', 'artificial intelligence', 'machine learning']).pluck(:id)

    @ai_companies_by_year = Company.joins(:taggings)
                                   .where(taggings: { tag_id: ai_tags })
                                   .where(visible: true)
                                   .where("founded_date ~ '^[0-9]{4}$'")
                                   .group("CAST(founded_date AS INTEGER)")
                                   .count
                                   .select { |year, _| year >= 2010 } # Filter for years >= 2010
                                   .sort_by { |year, _| year }

    @table_data = @ai_companies_by_year.map { |year, count| [year.to_s, count] }

    respond_to do |format|
      format.html
    end
  end

  def download_ai_trends
    ai_tags = Tag.where("LOWER(name) IN (?)", ['ai', 'artificial intelligence', 'machine learning']).pluck(:id)

    ai_companies_by_year = Company.joins(:taggings)
                                  .where(taggings: { tag_id: ai_tags })
                                  .where(visible: true)
                                  .where("founded_date ~ '^[0-9]{4}$'")
                                  .group("CAST(founded_date AS INTEGER)")
                                  .count
                                  .sort_by { |year, count| year }

    csv_data = ai_companies_by_year.map { |year, count| { year: year.to_s, count: count } }

    send_data generate_csv(csv_data, ['Year', 'AI Companies Founded']),
              filename: "ai_trends_analysis_#{Time.current.strftime('%Y%m%d')}.csv"
  end

  def category_evolution_5_years
    # Step 1: Get raw data from database - filter out Unknown category
    raw_data = Company.joins(:category)
                     .where(visible: true)
                     .where("founded_date ~ '^[0-9]{4}$'")
                     .where("CAST(founded_date AS INTEGER) >= 2000")
                     .where.not(categories: { name: 'Unknown' })
                     .group("categories.name", "CAST(founded_date AS INTEGER)")
                     .count

    # Step 2: Organize data by time period and calculate cumulative totals
    time_periods = {}

    # Define time periods
    periods = [
      "2005-2009",
      "2010-2014",
      "2015-2019",
      "2020-2024"
    ]

    # Get all unique categories
    all_categories = raw_data.keys.map { |(category, _)| category }.uniq

    # Define a consistent color palette for categories
    category_colors = {}
    color_palette = [
      "#8c1515", # Stanford Cardinal Red (keep this one)
      "#2986cc", # Muted Blue
      "#8e5fa2", # Muted Purple
      "#d55e00", # Muted Orange/Red
      "#37a4a6", # Muted Teal
      "#5a865a", # Muted Green
      "#ae6a59", # Muted Coral
      "#5b9bd5", # Steel Blue
      "#6b6b8d", # Slate Blue
      "#c67171"  # Muted Red
    ]

    all_categories.each_with_index do |category, index|
      category_colors[category] = color_palette[index % color_palette.length]
    end

    # Store category totals by year
    category_by_year = {}
    all_categories.each do |category|
      category_by_year[category] = {}
    end

    # Fill in raw yearly counts
    raw_data.each do |(category, year), count|
      category_by_year[category][year] = count
    end

    # Calculate cumulative totals for each period
    periods.each_with_index do |period, period_index|
      time_periods[period] = {}

      # Adjust the start year calculation since we're starting at 2005
      start_year = 2005 + (period_index * 5)
      end_year = start_year + 4

      all_categories.each do |category|
        # Sum all companies from this category up through this period
        time_periods[period][category] = 0

        # Count all companies founded from 2000 up through the end of this period
        (2000..end_year).each do |year|
          time_periods[period][category] += category_by_year[category].fetch(year, 0)
        end
      end
    end

    # Step 3: Prepare data for charts
    @period_data = {}
    @max_count = 0

    periods.each do |period|
      # Sort categories by count (descending) within each period
      period_categories = time_periods[period].sort_by { |_, count| -count }.to_h

      # Update max count for records
      max_in_period = period_categories.values.max || 0
      @max_count = max_in_period if max_in_period > @max_count

      # Store all categories for this period (we'll take top 9 in the view)
      @period_data[period] = period_categories
    end

    # Round max count up to nearest 50 for cleaner y-axis
    @max_count = ((@max_count / 50.0).ceil * 50)

    # Store colors for consistent rendering
    @category_colors = category_colors

    # Prepare stacked chart data for backward compatibility
    @chart_data = @period_data.map do |period, categories|
      {
        name: period,
        data: categories
      }
    end
  end

  def download_category_evolution_5_years
    # First ensure we have the data
    category_evolution_5_years if @period_data.nil?

    # Create CSV data from period data
    csv_data = CSV.generate do |csv|
      # Header row with periods
      csv << ['Category'] + @period_data.keys.to_a

      # Get all categories that appear in any period
      all_categories = @period_data.values.flat_map(&:keys).uniq

      # For each category, create a row with its count in each period
      all_categories.each do |category|
        row = [category]
        @period_data.each do |period, data|
          row << (data[category] || 0)
        end
        csv << row
      end
    end

    # Send the CSV data
    send_data csv_data,
              filename: "category_evolution_5_years_#{Time.current.strftime('%Y%m%d')}.csv",
              type: 'text/csv',
              disposition: 'attachment'
  end

  def funding_by_category
    # Get companies with funding data
    companies = Company.where(visible: true)
                      .where.not(total_funding_amount_usd: [nil, 0])
                      .includes(:category)
                      .where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
                             '2000',
                             Time.current.year.to_s,
                             '^\d{4}$')

    # Group by category and calculate funding metrics
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

    # Calculate total funding for market share percentage
    total_funding = funding_by_category.sum { |_, v| v[:total_funding] }

    # Prepare data for view
    @table_data = funding_by_category.map do |category, metrics|
      {
        category: category,
        total_funding: metrics[:total_funding],
        company_count: metrics[:company_count],
        avg_funding: metrics[:avg_funding],
        market_share: total_funding > 0 ? metrics[:total_funding] / total_funding * 100 : 0
      }
    end

    # Sort by total funding (descending)
    @table_data.sort_by! { |item| -item[:total_funding] }

    # Prepare chart data
    @chart_data = {
      name: 'Total Funding',
      data: @table_data.first(10).map { |d| [d[:category], d[:total_funding]] }
    }

    respond_to do |format|
      format.html
      format.csv do
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
                  type: 'text/csv',
                  disposition: 'attachment'
      end
      format.xlsx do
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
                  type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                  disposition: 'attachment'
      end
    end
  end

  def download_funding_by_category
    redirect_to statistics_funding_by_category_path(format: :csv)
  end

  private

  def visible_company_counts_by_year
    Rails.cache.fetch("statistics/visible_company_counts_by_year/#{Company.maximum(:updated_at)&.to_i}", expires_in: 10.minutes) do
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

  def extract_region(location)
    # Simple region mapping - could be made more sophisticated
    return "United States" if location.match?(/United States|USA|US$|California|New York|Texas/i)
    return "United Kingdom" if location.match?(/United Kingdom|UK|England|London/i)
    return "European Union" if location.match?(/Germany|France|Spain|Italy|Netherlands|Sweden|Denmark|Belgium/i)
    return "Canada" if location.match?(/Canada|Toronto|Vancouver|Montreal/i)
    return "Asia Pacific" if location.match?(/China|Japan|Singapore|Hong Kong|Australia|India/i)
    "Other"
  end

  def calculate_survival_rate(companies)
    # Companies still active after 5 years
    founded_before_5y = companies.count { |c| c.founded_date.to_i <= Time.current.year - 5 }
    return 0 if founded_before_5y.zero?

    still_active = companies.count { |c|
      founded_year = c.founded_date.to_i
      founded_year <= Time.current.year - 5 &&
      (c.exit_date.nil? || c.exit_date.year >= founded_year + 5)
    }

    (still_active / founded_before_5y.to_f * 100).round(1)
  end

  def calculate_funding_success(companies)
    # Companies that raised more than one round
    has_funding = companies.count { |c| c.total_funding_amount_usd.to_i > 0 }
    return 0 if has_funding.zero?

    multiple_rounds = companies.count { |c| c.number_of_funding_rounds.to_i > 1 }
    (multiple_rounds / has_funding.to_f * 100).round(1)
  end

  def calculate_exit_rate(companies)
    # Companies that had an exit (acquisition, IPO, etc)
    total = companies.count.to_f
    return 0 if total.zero?

    exits = companies.count { |c| c.exit_date.present? }
    (exits / total * 100).round(1)
  end

  def calculate_success_rate(companies)
    return 0 if companies.empty?
    successful = companies.count { |c| ['Public', 'Acquired'].include?(self.class.stage_mapping[c.funding_status]) }
    (successful / companies.count.to_f) * 100
  end

  def calculate_maturity_score(metrics)
    # Normalize and weight different factors
    company_score = [metrics[:total_companies] / 100.0, 1.0].min * 25  # Max 25 points
    age_score = [metrics[:avg_age] / 10.0, 1.0].min * 25              # Max 25 points
    funding_score = [metrics[:funding_rate] / 100.0, 1.0].min * 25    # Max 25 points
    stage_score = [metrics[:late_stage_rate] / 100.0, 1.0].min * 25   # Max 25 points

    # Calculate total score (0-100)
    total_score = (company_score + age_score + funding_score + stage_score).round(1)
    [total_score, 100.0].min  # Cap at 100
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

  def calculate_specialization_score(companies)
    return 0 if companies.empty?

    # Calculate how focused the region is on specific categories
    category_distribution = companies.group_by(&:category_id)
                                   .transform_values(&:count)

    total_companies = companies.size.to_f

    # Calculate Herfindahl-Hirschman Index (HHI)
    hhi = category_distribution.values.sum { |count| (count / total_companies) ** 2 }

    # Normalize to 0-100 scale
    (hhi * 100).round(1)
  end

  def calculate_funding_times(companies)
    funded_companies = companies.select { |c| c.total_funding_amount_usd.to_f > 0 }
    return { to_first: 0, between_rounds: 0 } if funded_companies.empty?

    # Average time to first funding
    times_to_first = funded_companies.map do |company|
      if company.founded_date.present?
        # This is a simplification - in reality, you'd want the date of first funding round
        company.founded_date.to_i
      end
    end.compact

    avg_to_first = if times_to_first.any?
      (times_to_first.sum / times_to_first.size.to_f).round(1)
    else
      0
    end

    # Average time between rounds
    avg_between = funded_companies.sum do |company|
      rounds = company.number_of_funding_rounds.to_i
      if rounds > 1
        # This is a simplification - in reality, you'd want actual times between rounds
        rounds / 2.0
      else
        0
      end
    end / funded_companies.size.to_f

    { to_first: avg_to_first, between_rounds: avg_between.round(1) }
  end

  def identify_growth_pattern(companies)
    return 'Insufficient Data' if companies.size < 5

    # Analyze funding patterns
    funded = companies.count { |c| c.total_funding_amount_usd.to_f > 0 }
    multiple_rounds = companies.count { |c| c.number_of_funding_rounds.to_i > 1 }

    if funded == 0
      'Bootstrap'
    elsif multiple_rounds > (funded * 0.7)
      'Venture-Backed'
    elsif multiple_rounds > (funded * 0.3)
      'Mixed'
    else
      'Single Round'
    end
  end

  def calculate_timing_impact(companies)
    # Group companies by founding year and calculate success metrics
    companies.group_by { |c| c.founded_date.to_i }
            .transform_values do |year_companies|
              {
                count: year_companies.size,
                success_rate: calculate_success_rate(year_companies),
                avg_funding: calculate_avg_funding(year_companies)
              }
            end
  end

  def generate_innovation_hubs_csv
    CSV.generate do |csv|
      csv << ['Region', 'Companies', 'Top Technologies', 'Diversity Index', 'YoY Growth', 'Specialization Score']
      @region_metrics.each do |region, metrics|
        csv << [
          region,
          metrics[:companies],
          metrics[:top_technologies].map { |t, c| "#{t} (#{c})" }.join('; '),
          metrics[:diversity_index],
          metrics[:yoy_growth],
          metrics[:specialization]
        ]
      end
    end
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

  def generate_founders_journey_csv
    CSV.generate do |csv|
      csv << ['Category', 'Companies', 'Avg Time to First Funding', 'Avg Time Between Rounds',
              'Success Rate', 'Growth Pattern']
      @lifecycle_metrics.each do |category, metrics|
        csv << [
          category,
          metrics[:companies],
          metrics[:avg_to_first_funding],
          metrics[:avg_between_rounds],
          metrics[:success_rate],
          metrics[:growth_pattern]
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
    return nil unless location
    # Split on comma and take the last part, which is typically the country
    parts = location.split(',').map(&:strip)
    country = parts.last

    # Handle common variations
    case country
    when 'USA', 'United States', 'US', 'U.S.', 'U.S.A.'
        'United States'
    when 'UK', 'United Kingdom', 'Great Britain'
        'United Kingdom'
    when 'UAE', 'U.A.E.'
        'United Arab Emirates'
    else
        country
    end
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
