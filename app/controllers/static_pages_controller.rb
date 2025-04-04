require 'csv'

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
  end

  def about
  end

  def statistics
  	if params[:founded_date]
  		@companies = Company.where(visible: true, founded_date: params[:founded_date]).all
  	else
  		@companies = Company.where(visible: true)
  	end

  	# Filter companies from year 2000 onwards and only valid years
  	@companies = @companies.where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
  								 '2000',
  								 Time.current.year.to_s,
  								 '^\d{4}$')

  	# Get unique years from 2000 onwards, sorted, only valid years
  	@years = Company.where(visible: true)
  				 .where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
  							'2000',
  							Time.current.year.to_s,
  							'^\d{4}$')
  				 .distinct
  				 .pluck(:founded_date)
  				 .sort
  				 .reject(&:blank?)

    # Get tag data for word cloud
    @tags = Tag.joins(:companies)
              .where(companies: { visible: true })
              .group('tags.id, tags.name')
              .having('COUNT(companies.id) > 2')
              .order('COUNT(companies.id) DESC')
              .limit(50)
              .select('tags.*, COUNT(companies.id) as count')
  end

  def total_companies
    # Get all companies founded from 2000 onwards with valid dates
    @companies = Company.where(visible: true)
                       .where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
                             '2000',
                             Time.current.year.to_s,
                             '^\d{4}$')

    # Get all years from 2000 to current
    start_year = 2000
    end_year = Time.current.year
    years = (start_year..end_year).to_a

    # Initialize yearly totals
    yearly_totals = Hash.new(0)
    years.each { |year| yearly_totals[year.to_s] = 0 }

    # Calculate cumulative totals by year
    @companies.each do |company|
      founded_year = company.founded_date.to_i
      next if founded_year < start_year || founded_year > end_year

      # Add to cumulative total for this year and all subsequent years
      years.each do |year|
        if year >= founded_year
          yearly_totals[year.to_s] += 1
        end
      end
    end

    # Format data for Chartkick
    @chart_data = {
      name: "Total Companies",
      data: yearly_totals
    }

    # Calculate year-over-year growth rates
    @table_data = years.map do |year|
      prev_year = (year - 1).to_s
      current_year = year.to_s

      total = yearly_totals[current_year]
      prev_total = yearly_totals[prev_year] || 0
      growth_rate = prev_total > 0 ? ((total - prev_total) / prev_total.to_f * 100) : 0

      {
        year: current_year,
        total_companies: total,
        new_companies: total - prev_total,
        growth_rate: growth_rate
      }
    end

    respond_to do |format|
      format.html
      format.csv do
        csv_data = CSV.generate do |csv|
          csv << ["Year", "Total Companies", "New Companies", "Growth Rate (%)"]
          @table_data.each do |data|
            csv << [
              data[:year],
              data[:total_companies],
              data[:new_companies],
              data[:growth_rate].round(1)
            ]
          end
        end
        send_data csv_data, filename: "total_companies_evolution.csv"
      end
    end
  end

  def category_evolution
    # Get all companies founded from 2000 onwards with valid dates
    @companies = Company.where(visible: true)
                       .where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
                             '2000',
                             Time.current.year.to_s,
                             '^\d{4}$')
                       .includes(:category) # Eager load categories

    # Get categories excluding Unknown and small categories
    excluded_categories = ['Unknown', 'Online Portals', 'Collaboration & Communication']
    categories = Category.where.not(name: excluded_categories)
                        .joins(:companies)
                        .group('categories.id')
                        .having('COUNT(companies.id) > 5') # Only include categories with more than 5 companies
                        .order(:name)

    # Initialize data structure for each category
    yearly_totals = {}
    categories.each do |category|
      yearly_totals[category.name] = Hash.new(0)
    end

    # Get all years from 2000 to current
    start_year = 2000
    end_year = Time.current.year
    years = (start_year..end_year).to_a

    # Initialize all years with zero for each category
    categories.each do |category|
      years.each do |year|
        yearly_totals[category.name][year.to_s] = 0
      end
    end

    # Calculate cumulative totals for each category by year
    @companies.each do |company|
      next if company.category.nil? || excluded_categories.include?(company.category.name)

      category_name = company.category.name
      next unless yearly_totals.key?(category_name) # Skip if category is not in our tracked categories

      founded_year = company.founded_date.to_i
      next if founded_year < start_year || founded_year > end_year # Skip invalid years

      # Add to cumulative total for this year and all subsequent years
      years.each do |year|
        if year >= founded_year
          yearly_totals[category_name][year.to_s] += 1
        end
      end
    end

    # Format data for Chartkick
    @chart_data = categories.map do |category|
      {
        name: category.name,
        data: yearly_totals[category.name]
      }
    end

    # Calculate growth metrics
    @growth_metrics = calculate_growth_metrics(categories)

    # Prepare table data
    @table_data = categories.map do |category|
      metrics = @growth_metrics[category.id]
      {
        name: category.name,
        total_companies: metrics[:total_companies],
        growth_rate: metrics[:growth_rate],
        avg_funding: calculate_avg_funding(companies_in_category(category))
      }
    end.sort_by { |d| -d[:total_companies] }

    # Calculate top growing categories for research notes
    @top_growing = @table_data.select { |d| d[:growth_rate] > 0 }
                             .sort_by { |d| -d[:growth_rate] }
                             .take(3)
                             .map { |d| d[:name] }

    # Calculate top funded categories for research notes
    @top_funded = @table_data.sort_by { |d| -d[:avg_funding] }
                            .take(3)
                            .map { |d| d[:name] }
  end

  def funding_concentration
    @companies = Company.where(visible: true)
                       .where.not(location: [nil, "", "Location unknown"])
                       .includes(:category)

    # Group companies by region and calculate metrics
    region_metrics = @companies.group_by { |c| extract_region(c.location) }
                              .transform_values do |companies|
      {
        companies: companies.count,
        total_funding: companies.sum(&:total_funding_amount_usd),
        avg_funding: companies.sum(&:total_funding_amount_usd) / companies.count.to_f
      }
    end

    # Prepare data for geo chart
    @region_data = region_metrics.transform_values { |v| v[:companies] }

    # Prepare data for table
    @region_table = region_metrics.map do |region, metrics|
      {
        region: region,
        companies: metrics[:companies],
        total_funding: metrics[:total_funding],
        avg_funding: metrics[:avg_funding]
      }
    end.sort_by { |d| -d[:companies] }

    # Calculate top regions for research notes
    @top_regions = @region_table.take(3).map { |d| d[:region] }
    @top_funded_regions = @region_table.sort_by { |d| -d[:total_funding] }
                                     .take(3)
                                     .map { |d| d[:region] }
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

  def growth_stage
    @companies = Company.where(visible: true).includes(:category)

    # Initialize stage data structure
    @stage_data = {}
    @stage_evolution = {}
    @stage_metrics = []

    # Count companies by stage
    @companies.each do |company|
      stage = self.class.stage_mapping[company.funding_status] || 'Operating'
      @stage_data[stage] ||= 0
      @stage_data[stage] += 1
    end

    # Calculate stage evolution over time
    (2000..Time.current.year).each do |year|
      @stage_evolution[year] = Hash.new(0)

      companies_until_year = @companies.select { |c| c.founded_date.to_i <= year }

      companies_until_year.each do |company|
        stage = self.class.stage_mapping[company.funding_status] || 'Operating'
        @stage_evolution[year][stage] += 1
      end
    end

    # Calculate metrics for each stage
    total_companies = @companies.count.to_f

    # Define stage order for consistent presentation
    stage_order = ['Seed', 'Early Stage', 'Late Stage', 'Private Equity', 'Public', 'Acquired', 'Operating']

    stage_order.each do |stage|
      next unless @stage_data[stage]

      count = @stage_data[stage]
      companies_in_stage = @companies.select { |c| (self.class.stage_mapping[c.funding_status] || 'Operating') == stage }

      # Calculate metrics
      metrics = {
        stage: stage,
        count: count,
        percentage: (count / total_companies * 100),
        avg_funding: calculate_avg_funding(companies_in_stage),
        success_rate: calculate_success_rate(companies_in_stage)
      }

      @stage_metrics << metrics
    end

    # Sort stages by count for the pie chart
    @stage_data = @stage_data.sort_by { |_, count| -count }.to_h
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

      metrics = {
        client: client_name,
        count: count,
        percentage: (count.to_f / total_companies * 100).round(1),
        avg_funding: calculate_avg_funding(client_companies[client_name])
      }

      @client_metrics << metrics
      @client_data[client_name] = count
    end

    # Sort by count descending
    @client_metrics.sort_by! { |m| -m[:count] }
    @client_data = @client_data.sort_by { |_, count| -count }.to_h
  end

  def country_distribution
    @companies = Company.where(visible: true)
                       .where('founded_date >= ? AND founded_date <= ? AND founded_date ~ ?',
                             '2000',
                             Time.current.year.to_s,
                             '^\d{4}$')

    # Group companies by country
    country_data = @companies.group_by do |company|
      location = company.location.to_s
      country = if location.include?(',')
                  location.split(',').last.strip
                else
                  location
                end

      # Map common variations to standard names
      case country
      when 'USA', 'United States of America', 'US'
        'United States'
      when 'UK'
        'United Kingdom'
      when 'UAE'
        'United Arab Emirates'
      else
        country
      end
    end

    # Calculate metrics for each country
    @country_metrics = country_data.transform_values do |companies|
      total_funding = companies.sum { |c| c.total_funding_amount_usd.to_f }
      {
        companies: companies.size,
        total_funding: total_funding,
        avg_funding: companies.any? ? (total_funding / companies.size) : 0
      }
    end

    # Prepare data for GeoChart
    @chart_data = @country_metrics.transform_keys do |country|
      # Map country names to ISO codes if needed
      country
    end

    # Prepare table data sorted by number of companies
    @table_data = @country_metrics.map do |country, metrics|
      {
        country: country,
        companies: metrics[:companies],
        total_funding: metrics[:total_funding],
        avg_funding: metrics[:avg_funding]
      }
    end.sort_by { |d| -d[:companies] }

    # Get top countries for research notes
    @top_countries = @table_data.take(5).map { |d| d[:country] }
    @top_funded_countries = @table_data.sort_by { |d| -d[:total_funding] }.take(5).map { |d| d[:country] }

    respond_to do |format|
      format.html
      format.csv do
        csv_data = CSV.generate do |csv|
          csv << ["Country", "Companies", "Total Funding", "Average Funding"]
          @table_data.each do |data|
            csv << [
              data[:country],
              data[:companies],
              data[:total_funding],
              data[:avg_funding]
            ]
          end
        end
        send_data csv_data, filename: "country_distribution.csv"
      end
    end
  end

  def download_category_evolution
    send_data generate_csv(@table_data, ['Category', 'Total Companies', 'Growth Rate']),
             filename: "category_evolution_#{Time.current.strftime('%Y%m%d')}.csv"
  end

  def download_funding_concentration
    send_data generate_csv(@region_table, ['Region', 'Companies', 'Total Funding', 'Avg Funding']),
             filename: "funding_concentration_#{Time.current.strftime('%Y%m%d')}.csv"
  end

  def download_category_success
    send_data generate_csv(@success_metrics, ['Category', 'Survival Rate', 'Funding Success', 'Exit Rate']),
             filename: "category_success_#{Time.current.strftime('%Y%m%d')}.csv"
  end

  def download_growth_stage
    send_data generate_csv(@stage_metrics, ['Stage', 'Companies', 'Percentage', 'Avg Funding']),
             filename: "growth_stage_#{Time.current.strftime('%Y%m%d')}.csv"
  end

  def download_business_model
    send_data generate_csv(@model_metrics, ['Business Model', 'Companies', 'Percentage', 'Avg Funding']),
             filename: "business_model_#{Time.current.strftime('%Y%m%d')}.csv"
  end

  def download_target_client
    send_data generate_csv(@client_metrics, ['Target Client', 'Companies', 'Percentage', 'Avg Funding']),
             filename: "target_client_#{Time.current.strftime('%Y%m%d')}.csv"
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
             .limit(25)

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

    # Calculate lifecycle metrics
    @lifecycle_metrics = {}

    Category.all.each do |category|
      category_companies = @companies.select { |c| c.category_id == category.id }
      next if category_companies.empty?

      # Calculate average time between major milestones
      funding_times = calculate_funding_times(category_companies)

      @lifecycle_metrics[category.name] = {
        companies: category_companies.size,
        avg_to_first_funding: funding_times[:to_first],
        avg_between_rounds: funding_times[:between_rounds],
        success_rate: calculate_success_rate(category_companies),
        growth_pattern: identify_growth_pattern(category_companies)
      }
    end

    # Sort by number of companies
    @lifecycle_metrics = @lifecycle_metrics.sort_by { |_, v| -v[:companies] }.to_h

    # Calculate timing impact
    @timing_impact = calculate_timing_impact(@companies)

    # Prepare chart data
    @success_rates = @lifecycle_metrics.transform_values { |v| v[:success_rate] }
    @funding_times = @lifecycle_metrics.transform_values { |v| v[:avg_to_first_funding] }

    respond_to do |format|
      format.html
      format.csv do
        send_data generate_founders_journey_csv,
                 filename: "founders_journey_analysis_#{Time.current.strftime('%Y%m%d')}.csv"
      end
    end
  end

  private

  def calculate_growth_metrics(categories)
    # Calculate metrics for each category
    categories.each_with_object({}) do |category, metrics|
      # Get companies in this category
      category_companies = @companies.select { |c| c.category == category }
      total = category_companies.count

      # Calculate growth rate using 5-year cumulative growth
      current_year = Time.current.year
      companies_now = category_companies.count { |c| c.founded_date.to_i <= current_year }
      companies_5y_ago = category_companies.count { |c| c.founded_date.to_i <= (current_year - 5) }

      growth_rate = if companies_5y_ago > 0
        ((companies_now.to_f / companies_5y_ago) - 1) * 100
      else
        companies_now > 0 ? 100 : 0
      end

      metrics[category.id] = {
        total_companies: total,
        growth_rate: growth_rate.round(1)
      }
    end
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
end
