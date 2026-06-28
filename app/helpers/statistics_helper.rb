module StatisticsHelper
  REGION_COUNTRY_COMPANIES_ROOT = "All companies".freeze
  REGION_COUNTRY_FUNDING_ROOT = "Disclosed funding".freeze
  REGION_SANKEY_TOP_COUNTRIES = 5

  STATS_CHART_PAGES = [
    { actions: %w[total_companies], title: "Total Companies", path: :statistics_total_companies_path },
    { actions: %w[country_distribution], title: "Geographic Distribution", path: :statistics_country_distribution_path },
    { actions: %w[category_evolution_5_years], title: "Industry Focus", path: :statistics_category_evolution_5_years_path },
    { actions: %w[funding_by_category], title: "Funding", path: :statistics_funding_by_category_path },
    { actions: %w[target_client], title: "Market Focus", path: :statistics_target_client_path },
    { actions: %w[ai_trends], title: "AI in Legal Tech", path: :statistics_ai_trends_path },
    { actions: %w[business_model], title: "Revenue Model Insights", path: :statistics_business_model_path },
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

  def stats_country_distribution_preview(top_count: 4)
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

  def stats_geographic_distribution_scope
    Company.where(visible: true)
           .where.not(location: [nil, "", "Location unknown"])
           .where("founded_date >= ? AND founded_date <= ? AND founded_date ~ ?", "2000", Time.current.year.to_s, '^\d{4}$')
  end
end
