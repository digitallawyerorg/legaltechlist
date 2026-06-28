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

  STATS_CHART_PAGES = [
    { actions: %w[total_companies], title: "Total Companies", path: :statistics_total_companies_path },
    { actions: %w[country_distribution], title: "Geographic Distribution", path: :statistics_country_distribution_path },
    { actions: %w[category_evolution_5_years], title: "Industry Focus", path: :statistics_category_evolution_5_years_path },
    { actions: %w[funding_by_category], title: "Funding", path: :statistics_funding_by_category_path },
    { actions: %w[ai_trends], title: "AI in Legal Tech", path: :statistics_ai_trends_path },
    { actions: %w[tag_distribution], title: "Technology Themes", path: :statistics_tag_distribution_path }
  ].freeze

  def stats_chart_neighbors
    index = STATS_CHART_PAGES.find_index { |page| page[:actions].include?(action_name) }
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
      country = LocationCountryResolver.country_name_for(company.location)
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
      country = LocationCountryResolver.country_name_for(company.location)
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

  private

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
    stats_index_scope.where.not(location: [nil, "", "Location unknown"])
  end
end
