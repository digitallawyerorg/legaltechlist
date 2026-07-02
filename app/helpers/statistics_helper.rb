module StatisticsHelper
  REGION_COUNTRY_COMPANIES_ROOT = "All companies".freeze
  REGION_COUNTRY_FUNDING_ROOT = "Disclosed funding".freeze
  REGION_SANKEY_TOP_COUNTRIES = 5

  VENTURE_STAGE_ORDER = [
    "Operating",
    "Seed",
    "Early Stage Venture",
    "Late Stage Venture",
    "Private Equity",
    "M&A",
    "IPO",
    "Unclassified"
  ].freeze

  VENTURE_STAGE_ALIASES = {
    "For Profit" => "Operating"
  }.freeze

  VENTURE_STAGE_SHORT_LABELS = {
    "Operating" => "Operating",
    "Seed" => "Seed",
    "Early Stage Venture" => "Early stage",
    "Late Stage Venture" => "Late stage",
    "Private Equity" => "Private equity",
    "M&A" => "M&A",
    "IPO" => "IPO",
    "Unclassified" => "Other"
  }.freeze

  STATS_INDEX_CHART_COLORS = [
    "#8c1515", "#175e54", "#2986cc", "#8e5fa2", "#d55e00", "#37a4a6",
    "#5a865a", "#ae6a59", "#5b9bd5", "#6b6b8d", "#c67171", "#820000"
  ].freeze

  COVERAGE_HEATMAP_REGION_ORDER = [
    "North America", "Europe", "Asia-Pacific", "Latin America", "Middle East", "Africa", "Other"
  ].freeze

  COVERAGE_HEATMAP_DIMENSIONS = [
    { key: "category", label: "Category", secondary: "Region" },
    { key: "business_model", label: "Business model", secondary: "Region" },
    { key: "location", label: "Location", secondary: "Category" },
    { key: "target_market", label: "Target market", secondary: "Region" },
    { key: "fundraising", label: "Fundraising", secondary: "Region" }
  ].freeze

  COVERAGE_HEATMAP_OTHER_LABEL = "Other".freeze
  COVERAGE_HEATMAP_ROW_LIMIT = 10
  COVERAGE_HEATMAP_COLUMN_LIMIT = 8
  COVERAGE_HEATMAP_MIN_RATIO = 0.14

  # ColorBrewer diverging RdYlGn (red -> yellow -> green). Low/sparse coverage
  # reads red, mid amber, and well-covered cells green.
  COVERAGE_HEATMAP_RAMP = [
    [215, 48, 39], [244, 109, 67], [253, 174, 97], [254, 224, 139], [255, 255, 191],
    [217, 239, 139], [166, 217, 106], [102, 189, 99], [26, 152, 80]
  ].freeze

  STATS_CHART_PAGES = [
    { actions: %w[total_companies], title: "Total Companies", path: :statistics_total_companies_path },
    { actions: %w[country_distribution], title: "Geographic Distribution", path: :statistics_country_distribution_path },
    { actions: %w[category_evolution_5_years], title: "Category Expansion", path: :statistics_category_evolution_5_years_path },
    { actions: %w[category_evolution_5_years], title: "Business Model", path: :statistics_business_model_path },
    { actions: %w[category_evolution_5_years], title: "Target Audience", path: :statistics_target_client_path },
    { actions: %w[funding_by_category], dimension: "category", title: "Funding by Category", path: :statistics_funding_by_category_path },
    { actions: %w[funding_by_category], dimension: "region", title: "Funding by Region", path: :statistics_funding_by_region_path },
    { actions: %w[ai_trends], title: "AI in Legal Tech", path: :statistics_ai_trends_path },
    { actions: %w[tag_distribution], title: "Technology Themes", path: :statistics_tag_distribution_path },
    { actions: %w[data_coverage], title: "Data Coverage", path: :statistics_data_coverage_path }
  ].freeze

  def stats_chart_neighbors
    index = STATS_CHART_PAGES.find_index { |page| stats_chart_page_match?(page) }
    return nil unless index

    page_count = STATS_CHART_PAGES.size
    prev_page = STATS_CHART_PAGES[(index - 1) % page_count]
    next_page = STATS_CHART_PAGES[(index + 1) % page_count]

    {
      prev: { title: prev_page[:title], path: public_send(prev_page[:path]) },
      next: { title: next_page[:title], path: public_send(next_page[:path]) }
    }
  end

  def region_country_chart_label(region, country)
    region == country ? "#{country} (country)" : country
  end

  def region_country_sankey_other_label(region)
    "Other (#{region})"
  end

  def region_country_sankey_data(region_country_metrics, root: REGION_COUNTRY_COMPANIES_ROOT, value_key: :companies, top_countries: REGION_SANKEY_TOP_COUNTRIES)
    nodes = [{ name: root }]
    links = []
    node_names = [root]
    total = region_country_metrics.values.sum { |countries| countries.values.sum { |metrics| metrics[value_key].to_f } }

    region_country_metrics.sort_by { |_, countries| -countries.values.sum { |metrics| metrics[value_key].to_f } }.each do |region, countries|
      region_total = countries.values.sum { |metrics| metrics[value_key].to_f }
      next unless region_total.positive?

      unless node_names.include?(region)
        nodes << { name: region }
        node_names << region
      end

      links << { source: root, target: region, value: region_total }

      sorted_countries = countries.sort_by { |_, metrics| -metrics[value_key].to_f }
      top_rows, other_rows = sorted_countries.partition.with_index { |_, index| index < top_countries }

      top_rows.each do |country, metrics|
        value = metrics[value_key].to_f
        next unless value.positive?

        label = region_country_chart_label(region, country)
        unless node_names.include?(label)
          nodes << { name: label }
          node_names << label
        end

        links << { source: region, target: label, value: value }
      end

      other_total = other_rows.sum { |_, metrics| metrics[value_key].to_f }
      next unless other_total.positive?

      other_label = region_country_sankey_other_label(region)
      unless node_names.include?(other_label)
        nodes << { name: other_label }
        node_names << other_label
      end

      links << { source: region, target: other_label, value: other_total }
    end

    { nodes: nodes, links: links, total: total, value_key: value_key.to_s }
  end

  def region_country_sunburst_tree(region_country_metrics, root: REGION_COUNTRY_COMPANIES_ROOT, value_key: :companies)
    {
      name: root,
      children: region_country_metrics.sort_by { |_, countries| -countries.values.sum { |metrics| metrics[value_key].to_f } }.filter_map do |region, countries|
        region_children = countries.sort_by { |_, metrics| -metrics[value_key].to_f }.filter_map do |country, metrics|
          value = metrics[value_key].to_f
          next unless value.positive?

          {
            name: region_country_chart_label(region, country),
            value: value
          }
        end
        next if region_children.empty?

        {
          name: region,
          children: region_children
        }
      end
    }
  end

  def build_region_table_data(region_country_metrics)
    region_country_metrics.map do |region, countries|
      country_rows = countries.map do |country, metrics|
        avg_funding = metrics[:funded_companies].positive? ? metrics[:total_funding] / metrics[:funded_companies] : 0

        {
          country: country,
          companies: metrics[:companies],
          total_funding: metrics[:total_funding],
          avg_funding: avg_funding
        }
      end.sort_by { |row| -row[:companies] }

      region_totals = country_rows.each_with_object({ companies: 0, total_funding: 0.0, funded_companies: 0 }) do |row, totals|
        totals[:companies] += row[:companies]
        totals[:total_funding] += row[:total_funding]
      end

      funded_companies = countries.values.sum { |metrics| metrics[:funded_companies] }
      avg_funding = funded_companies.positive? ? region_totals[:total_funding] / funded_companies : 0
      country_label = country_rows.size == 1 ? country_rows.first[:country] : nil

      {
        region: region,
        country_label: country_label,
        companies: region_totals[:companies],
        total_funding: region_totals[:total_funding],
        avg_funding: avg_funding,
        countries: country_label ? [] : country_rows
      }
    end.sort_by { |row| -row[:companies] }
  end

  def build_funding_region_table_data(region_country_metrics)
    build_region_table_data(region_country_metrics).sort_by { |row| -row[:total_funding] }.map do |region_data|
      region_data.merge(
        countries: region_data[:countries].sort_by { |row| -row[:total_funding] }
      )
    end
  end

  def stats_country_distribution_preview(top_count: 3)
    country_counts = Hash.new(0)
    total = 0

    stats_geographic_distribution_scope.find_each do |company|
      country = stats_normalized_country(company)
      next if country.blank?

      country_counts[country] += 1
      total += 1
    end

    return [] unless total.positive?

    sorted = country_counts.sort_by { |_, count| -count }
    top_rows, rest_rows = sorted.partition.with_index { |_, index| index < top_count }
    rest_count = rest_rows.sum { |_, count| count }

    rows = top_rows.map { |country, count| { label: country, share: ((count.to_f / total) * 100).round } }
    if rest_count.positive?
      rows << { label: "Rest of world", share: 100 - rows.sum { |row| row[:share] } }
    end
    rows
  end

  def stats_region_distribution_preview(top_count: 3)
    region_counts = Hash.new(0)
    total = 0

    stats_geographic_distribution_scope.find_each do |company|
      country = stats_normalized_country(company)
      next if country.blank?

      region = LocationRegionResolver.region_for_country(country)
      region_counts[region] += 1
      total += 1
    end

    return [] unless total.positive?

    sorted = region_counts.sort_by { |_, count| -count }
    top_rows, rest_rows = sorted.partition.with_index { |_, index| index < top_count }
    rest_count = rest_rows.sum { |_, count| count }

    rows = top_rows.map { |region, count| { label: region, share: ((count.to_f / total) * 100).round } }
    if rest_count.positive?
      rows << { label: "Rest of world", share: 100 - rows.sum { |row| row[:share] } }
    end
    rows
  end

  def canonical_venture_stage_name(raw_status)
    status = raw_status.to_s.strip
    return "Unclassified" if status.blank?

    aliased = VENTURE_STAGE_ALIASES[status] || status
    VENTURE_STAGE_ORDER.include?(aliased) ? aliased : "Unclassified"
  end

  def stats_index_chart_colors(count, offset: 0)
    STATS_INDEX_CHART_COLORS.cycle.take(count + offset).drop(offset)
  end

  def build_venture_stage_metrics
    stage_counts = VENTURE_STAGE_ORDER.index_with { 0 }
    companies = stats_index_scope.to_a

    companies.each do |company|
      stage_counts[canonical_venture_stage_name(company.funding_status)] += 1
    end

    total = companies.size.to_f
    stage_metrics = VENTURE_STAGE_ORDER.filter_map do |stage|
      count = stage_counts[stage]
      next if count.zero?

      {
        stage: stage,
        count: count,
        percentage: total.positive? ? (count / total * 100).round(1) : 0
      }
    end

    {
      stage_metrics: stage_metrics,
      stage_data: stage_metrics.to_h { |row| [row[:stage], row[:count]] }
    }
  end

  def stats_venture_stage_preview(top_count: 3)
    rows = build_venture_stage_metrics[:stage_metrics].sort_by { |row| -row[:count] }.map do |row|
      {
        label: VENTURE_STAGE_SHORT_LABELS.fetch(row[:stage], row[:stage]),
        share: row[:percentage]
      }
    end
    stats_share_preview_rows(rows, top_count: top_count)
  end

  def stats_ecosystem_growth_bar_preview(segment_count: 8)
    end_year = Time.current.year
    years = ((end_year - segment_count + 1)..end_year).to_a
    values = years.map { |year| stats_index_scope.where("CAST(founded_date AS INTEGER) <= ?", year).count }
    stats_vertical_bar_segments(values)
  end

  def stats_ecosystem_growth_trend(point_count: 9)
    end_year = Time.current.year
    years = ((end_year - point_count + 1)..end_year).to_a
    values = years.map do |year|
      stats_index_scope.where("CAST(founded_date AS INTEGER) <= ?", year).count
    end
    stats_trend_area_paths(values)
  end

  def stats_industry_focus_trend(point_count: 9)
    end_year = Time.current.year
    years = ((end_year - point_count + 1)..end_year).to_a
    top_category = stats_index_scope.joins(:category).where.not(categories: { name: "Unknown" }).group("categories.name").order(Arel.sql("COUNT(*) DESC")).limit(1).pick("categories.name")
    return stats_trend_area_paths([0]) if top_category.blank?

    values = years.map do |year|
      stats_index_scope.joins(:category).where(categories: { name: top_category }).where("CAST(founded_date AS INTEGER) <= ?", year).count
    end
    stats_trend_area_paths(values)
  end

  def stats_ai_trends_trend(point_count: 9)
    ai_tags = TagNormalizationService.ai_related_tag_ids
    end_year = Time.current.year
    years = ((end_year - point_count + 1)..end_year).to_a
    values = years.map do |year|
      Company.joins(:taggings)
             .where(taggings: { tag_id: ai_tags })
             .merge(stats_index_scope)
             .where("CAST(founded_date AS INTEGER) <= ?", year)
             .distinct
             .count
    end
    stats_trend_area_paths(values)
  end

  def stats_venture_stage_funnel_segments(top_count: 3)
    stage_data = build_venture_stage_metrics[:stage_data]
    rows = VENTURE_STAGE_ORDER.filter_map do |stage|
      count = stage_data[stage].to_i
      next if count.zero? || stage == "Unclassified"

      { label: stage, share: count }
    end.sort_by { |row| -row[:share] }

    preview_rows = stats_share_preview_rows(rows, top_count: top_count)
    stats_vertical_bar_segments(preview_rows.map { |row| row[:share] })
  end

  def stats_tag_distribution_preview(top_count: 3)
    counts = Tag.joins(:companies)
                .merge(Company.where(visible: true))
                .group("tags.name")
                .order(Arel.sql("COUNT(DISTINCT companies.id) DESC"))
                .limit(8)
                .count
    rows = counts.map { |name, count| { label: name, share: count } }
    stats_share_preview_rows(rows, top_count: top_count)
  end

  def stats_funding_category_preview(top_count: 3)
    totals = Hash.new(0.0)
    stats_index_scope.includes(:category).where("total_funding_amount_usd > 0").find_each do |company|
      category_name = company.category&.name
      next if category_name.blank? || category_name == "Unknown"

      totals[category_name] += company.total_funding_amount_usd.to_f
    end

    stats_share_preview_rows(totals.sort_by { |_, amount| -amount }.map { |label, amount| { label: label, share: amount } }, top_count: top_count)
  end

  def stats_funding_region_preview(top_count: 3)
    totals = Hash.new(0.0)
    stats_geographic_distribution_scope.where("total_funding_amount_usd > 0").find_each do |company|
      country = stats_normalized_country(company)
      next if country.blank?

      region = LocationRegionResolver.region_for_country(country)
      totals[region] += company.total_funding_amount_usd.to_f
    end

    stats_share_preview_rows(totals.sort_by { |_, amount| -amount }.map { |label, amount| { label: label, share: amount } }, top_count: top_count, rest_label: "Rest of world")
  end

  def stats_revenue_model_preview(top_count: 3)
    model_counts = Hash.new(0)
    stats_index_scope.includes(:business_models, :business_model).find_each do |company|
      TaxonomyNormalizationService.canonical_revenue_model_names(company.revenue_model_names.join(", ")).each do |model_name|
        model_counts[model_name] += 1
      end
    end

    total = model_counts.values.sum.to_f
    rows = model_counts.sort_by { |_, count| -count }.map do |label, count|
      { label: label, share: total.positive? ? ((count / total) * 100).round : 0 }
    end
    stats_share_preview_rows(rows, top_count: top_count)
  end

  def stats_compact_funding(amount)
    amount = amount.to_f
    return "$0" unless amount.positive?

    if amount >= 1_000_000_000
      "$#{(amount / 1_000_000_000).round(1).to_s.sub(/\.0$/, '')}B"
    elsif amount >= 1_000_000
      "$#{(amount / 1_000_000).round}M"
    else
      number_to_currency(amount, precision: 0)
    end
  end

  def stats_index_category_count
    stats_index_scope.joins(:category).where.not(categories: { name: "Unknown" }).distinct.count("categories.id")
  end

  def stats_index_business_model_count
    model_names = Set.new
    stats_index_scope.includes(:business_models, :business_model).find_each do |company|
      TaxonomyNormalizationService.canonical_revenue_model_names(company.revenue_model_names.join(", ")).each do |model_name|
        model_names << model_name
      end
    end
    model_names.size
  end

  def stats_index_target_market_count
    client_names = Set.new
    stats_geographic_distribution_scope.includes(:target_client, :target_clients).find_each do |company|
      company.audience_names.each do |target|
        next if target.blank? || target == "Unknown"

        client_names << target
      end
    end
    client_names.size
  end

  def stats_index_total_funding_amount
    stats_index_scope.where("total_funding_amount_usd > 0").sum(:total_funding_amount_usd).to_f
  end

  def stats_index_funding_country_count
    countries = Set.new
    stats_geographic_distribution_scope.where("total_funding_amount_usd > 0").find_each do |company|
      country = stats_normalized_country(company)
      countries << country if country.present?
    end
    countries.size
  end

  def stats_index_ai_company_count
    ai_tags = TagNormalizationService.ai_related_tag_ids
    Company.joins(:taggings)
           .where(taggings: { tag_id: ai_tags })
           .merge(stats_index_scope)
           .distinct
           .count
  end

  def stats_index_tag_count
    Tag.joins(:companies)
       .where(companies: { visible: true })
       .group("LOWER(REGEXP_REPLACE(tags.name, E'\\s+', ' ', 'g'))")
       .having("COUNT(DISTINCT companies.id) > 8")
       .count
       .size
  end

  def stats_target_client_preview(top_count: 3)
    client_counts = Hash.new(0)
    total = 0

    stats_geographic_distribution_scope.includes(:target_client, :target_clients).find_each do |company|
      company.audience_names.each do |target|
        next if target.blank? || target == "Unknown"

        client_counts[target] += 1
        total += 1
      end
    end

    return [] unless total.positive?

    sorted = client_counts.sort_by { |_, count| -count }
    top_rows, rest_rows = sorted.partition.with_index { |_, index| index < top_count }
    rest_count = rest_rows.sum { |_, count| count }

    rows = top_rows.map { |client, count| { label: client, share: ((count.to_f / total) * 100).round } }
    if rest_count.positive?
      rows << { label: "Rest", share: 100 - rows.sum { |row| row[:share] } }
    end
    rows
  end

  def stats_coverage_heatmap_dimensions
    COVERAGE_HEATMAP_DIMENSIONS
  end

  def build_coverage_heatmaps
    category_region = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    business_model_region = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    target_region = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    stage_region = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    region_category = Hash.new { |hash, key| hash[key] = Hash.new(0) }

    stats_index_scope.includes(:category, :business_models, :business_model, :target_clients, :target_client).find_each do |company|
      region = coverage_heatmap_region_for(company)
      category = coverage_heatmap_category_for(company)
      stage = canonical_venture_stage_name(company.funding_status)
      business_models = TaxonomyNormalizationService.canonical_revenue_model_names(company.revenue_model_names.join(", ")).uniq
      targets = company.audience_names.reject { |target| target.blank? || target == "Unknown" }.uniq

      if region
        category_region[category][region] += 1 if category
        business_models.each { |model| business_model_region[model][region] += 1 }
        targets.each { |target| target_region[target][region] += 1 }
        stage_region[stage][region] += 1
        region_category[region][category] += 1 if category
      end
    end

    {
      "category" => coverage_heatmap_grid(category_region, primary_label: "Category", secondary_label: "Region", column_order: COVERAGE_HEATMAP_REGION_ORDER),
      "business_model" => coverage_heatmap_grid(business_model_region, primary_label: "Business model", secondary_label: "Region", column_order: COVERAGE_HEATMAP_REGION_ORDER),
      "location" => coverage_heatmap_grid(region_category, primary_label: "Location", secondary_label: "Category", row_order: COVERAGE_HEATMAP_REGION_ORDER),
      "target_market" => coverage_heatmap_grid(target_region, primary_label: "Target market", secondary_label: "Region", column_order: COVERAGE_HEATMAP_REGION_ORDER),
      "fundraising" => coverage_heatmap_grid(stage_region, primary_label: "Fundraising", secondary_label: "Region", column_order: COVERAGE_HEATMAP_REGION_ORDER, row_order: VENTURE_STAGE_ORDER)
    }
  end

  def stats_coverage_heatmap_preview(row_count: 3, column_count: 4)
    category_region = Hash.new { |hash, key| hash[key] = Hash.new(0) }

    stats_index_scope.includes(:category).find_each do |company|
      region = coverage_heatmap_region_for(company)
      category = coverage_heatmap_category_for(company)
      next unless region && category

      category_region[category][region] += 1
    end

    region_totals = Hash.new(0)
    category_region.each_value { |regions| regions.each { |region, value| region_totals[region] += value } }
    ranked_regions = COVERAGE_HEATMAP_REGION_ORDER.select { |region| region_totals[region].positive? }.sort_by { |region| -region_totals[region] }

    columns =
      if ranked_regions.size > column_count
        ranked_regions.first(column_count - 1) + [ranked_regions.last]
      else
        ranked_regions.first(column_count)
      end

    ranked_categories = category_region.sort_by { |_, regions| -regions.values.sum }.map(&:first)
    gap_categories = ranked_categories.select { |category| columns.any? { |region| category_region[category][region].to_i.zero? } }
    chosen = (ranked_categories.first(row_count - 1) + gap_categories).uniq.first(row_count)
    chosen = ranked_categories.first(row_count) if chosen.size < row_count

    rows = chosen.map do |category|
      { label: category, cells: columns.map { |region| category_region[category][region].to_i } }
    end
    max = rows.flat_map { |row| row[:cells] }.max.to_i

    { columns: columns, rows: rows, max: max }
  end

  def coverage_heatmap_grid(counts, primary_label:, secondary_label:, column_order: nil, row_order: nil, row_limit: COVERAGE_HEATMAP_ROW_LIMIT, column_limit: COVERAGE_HEATMAP_COLUMN_LIMIT)
    counts = counts.transform_values { |columns| columns.reject { |_, value| value.to_i.zero? } }.reject { |_, columns| columns.empty? }

    column_totals = Hash.new(0)
    counts.each_value { |columns| columns.each { |label, value| column_totals[label] += value } }

    if column_order
      columns = column_order.select { |label| column_totals[label].to_i.positive? }
      overflow_columns = []
    else
      ranked_columns = column_totals.sort_by { |label, total| [-total, label] }.map(&:first)
      columns = ranked_columns.first(column_limit)
      overflow_columns = ranked_columns.drop(column_limit)
    end
    column_labels = columns + (overflow_columns.any? ? [COVERAGE_HEATMAP_OTHER_LABEL] : [])

    row_totals = counts.transform_values { |cols| cols.values.sum }
    ordered_rows =
      if row_order
        (row_order & counts.keys) + counts.keys.reject { |label| row_order.include?(label) }.sort_by { |label| [-row_totals[label], label] }
      else
        counts.keys.sort_by { |label| [-row_totals[label], label] }
      end
    ordered_rows = ordered_rows.select { |label| row_totals[label].to_i.positive? }

    top_rows = ordered_rows.first(row_limit)
    overflow_rows = ordered_rows.drop(row_limit)

    rows = top_rows.map do |label|
      { label: label, total: row_totals[label], cells: coverage_heatmap_row_cells(counts[label], columns, overflow_columns) }
    end

    if overflow_rows.any?
      merged = Hash.new(0)
      overflow_rows.each { |label| counts[label].each { |col, value| merged[col] += value } }
      rows << { label: COVERAGE_HEATMAP_OTHER_LABEL, total: overflow_rows.sum { |label| row_totals[label] }, cells: coverage_heatmap_row_cells(merged, columns, overflow_columns) }
    end

    max = rows.flat_map { |row| row[:cells] }.max.to_i

    { primary_label: primary_label, secondary_label: secondary_label, columns: column_labels, rows: rows, max: max }
  end

  def coverage_heatmap_ramp_rgb(ratio)
    ratio = ratio.to_f.clamp(0.0, 1.0)
    stops = COVERAGE_HEATMAP_RAMP
    scaled = ratio * (stops.size - 1)
    lower = scaled.floor
    upper = [lower + 1, stops.size - 1].min
    weight = scaled - lower
    [0, 1, 2].map { |channel| (stops[lower][channel] + (stops[upper][channel] - stops[lower][channel]) * weight).round }
  end

  def coverage_heatmap_scale_color(ratio)
    "rgb(#{coverage_heatmap_ramp_rgb(ratio).join(', ')})"
  end

  def coverage_heatmap_text_color(ratio)
    red, green, blue = coverage_heatmap_ramp_rgb(ratio)
    luminance = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255.0
    luminance > 0.62 ? "#2a2723" : "#ffffff"
  end

  def coverage_heatmap_count_ratio(count, max)
    count = count.to_i
    return 0.0 if count <= 0

    max = 1 if max.to_i < 1
    ratio = Math.sqrt(count.to_f / max.to_f)
    ratio < COVERAGE_HEATMAP_MIN_RATIO ? COVERAGE_HEATMAP_MIN_RATIO : ratio
  end

  def coverage_heatmap_percent_ratio(percent, percent_max)
    percent = percent.to_f
    return 0.0 if percent <= 0

    percent_max = percent.to_f if percent_max.to_f <= 0
    (percent / percent_max.to_f).clamp(0.0, 1.0)
  end

  def coverage_heatmap_percent_label(count, percent)
    return "0%" if count.to_i <= 0
    return "<1%" if percent.to_f < 0.5

    "#{percent.round}%"
  end

  def coverage_heatmap_cell_presentation(value, max)
    value = value.to_i
    return { value: value, gap: true, background: nil, text_color: nil, ratio: 0.0 } if value <= 0

    ratio = coverage_heatmap_count_ratio(value, max)

    {
      value: value,
      gap: false,
      background: coverage_heatmap_scale_color(ratio),
      text_color: coverage_heatmap_text_color(ratio),
      ratio: ratio.round(3)
    }
  end

  def coverage_heatmap_row_display(row, count_max)
    total = row[:total].to_i
    percents = row[:cells].map { |count| total.positive? ? (count.to_f / total * 100) : 0.0 }
    percent_max = percents.max.to_f

    cells = row[:cells].each_with_index.map do |count, index|
      coverage_heatmap_cell_display(count.to_i, count_max, percents[index], percent_max)
    end

    { label: row[:label], total: total, cells: cells }
  end

  def coverage_heatmap_cell_display(count, count_max, percent, percent_max)
    count = count.to_i
    gap = count <= 0
    count_ratio = coverage_heatmap_count_ratio(count, count_max)
    percent_ratio = coverage_heatmap_percent_ratio(percent, percent_max)

    {
      count: count,
      percent: percent.round(1),
      percent_label: coverage_heatmap_percent_label(count, percent),
      gap: gap,
      count_background: gap ? nil : coverage_heatmap_scale_color(count_ratio),
      count_text_color: gap ? nil : coverage_heatmap_text_color(count_ratio),
      percent_background: gap ? nil : coverage_heatmap_scale_color(percent_ratio),
      percent_text_color: gap ? nil : coverage_heatmap_text_color(percent_ratio)
    }
  end

  private

  def stats_normalized_country(company)
    country = company.resolved_country
    return if country.blank?

    LocationCountryResolver.normalize_country_name(country)
  end

  def coverage_heatmap_region_for(company)
    country = stats_normalized_country(company)
    return nil if country.blank?

    LocationRegionResolver.region_for_country(country)
  end

  def coverage_heatmap_category_for(company)
    name = company.category&.name
    return nil if name.blank? || name == "Unknown"

    name
  end

  def coverage_heatmap_row_cells(column_counts, columns, overflow_columns)
    column_counts ||= {}
    cells = columns.map { |label| column_counts[label].to_i }
    cells << overflow_columns.sum { |label| column_counts[label].to_i } if overflow_columns.any?
    cells
  end

  def stats_chart_page_match?(page)
    return false unless page[:actions].include?(action_name)

    return true unless page.key?(:dimension)

    current_dimension = params[:dimension].presence || (params[:view] == "region" ? "region" : nil) || "category"
    page[:dimension] == current_dimension
  end

  def stats_share_preview_rows(rows, top_count: 3, rest_label: "Rest")
    return [] if rows.empty?

    total_share = rows.sum { |row| row[:share].to_f }
    return [] unless total_share.positive?

    top_rows = rows.first(top_count)
    rest_share = total_share - top_rows.sum { |row| row[:share].to_f }
    preview_rows = top_rows.map { |row| { label: row[:label], share: ((row[:share].to_f / total_share) * 100).round } }
    preview_rows << { label: rest_label, share: 100 - preview_rows.sum { |row| row[:share] } } if rest_share.positive?
    preview_rows
  end

  def stats_vertical_bar_segments(values)
    values = Array(values)
    return [] if values.empty?

    max_value = values.max.to_f
    max_value = 1.0 if max_value <= 0
    values.map { |value| (value / max_value * 100).round(1) }
  end

  def stats_trend_area_paths(values, width: 240.0, height: 48.0)
    values = Array(values)
    return { line_path: "M0,#{height} L#{width},#{height}", area_path: "M0,#{height} L#{width},#{height} L#{width},#{height} L0,#{height} Z" } if values.empty?

    max_value = [values.max.to_f, 1.0].max
    points = values.each_with_index.map do |value, index|
      x = (index.to_f / [values.size - 1, 1].max * width).round(1)
      y = (height - (value / max_value * (height - 8)) - 4).round(1)
      [x, y]
    end
    line_path = points.map.with_index { |(x, y), index| index.zero? ? "M#{x},#{y}" : "L#{x},#{y}" }.join(" ")
    area_path = "#{line_path} L#{width},#{height} L0,#{height} Z"
    { line_path: line_path, area_path: area_path }
  end

  def stats_index_scope
    Company.where(visible: true)
           .where("founded_date >= ? AND founded_date <= ? AND founded_date ~ ?", "2000", Time.current.year.to_s, '^\d{4}$')
  end

  def stats_geographic_distribution_scope
    stats_index_scope.where.not(country: [nil, ""]).or(
      stats_index_scope.where(country: [nil, ""]).where.not(location: [nil, "", "Location unknown"])
    )
  end
end
