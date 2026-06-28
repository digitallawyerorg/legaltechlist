module StatisticsHelper
  REGION_COUNTRY_COMPANIES_ROOT = "All companies".freeze
  REGION_COUNTRY_FUNDING_ROOT = "Disclosed funding".freeze
  REGION_SANKEY_TOP_COUNTRIES = 5

  STATS_CHART_PAGES = [
    { actions: %w[total_companies], title: "Total Companies", path: :statistics_total_companies_path },
    { actions: %w[country_distribution], title: "Geographic Distribution", path: :statistics_country_distribution_path },
    { actions: %w[category_evolution_5_years], title: "Category Evolution", path: :statistics_category_evolution_5_years_path },
    { actions: %w[tag_distribution], title: "Technology Themes", path: :statistics_tag_distribution_path },
    { actions: %w[target_client], title: "Market Focus", path: :statistics_target_client_path },
    { actions: %w[ai_trends], title: "AI in Legal Tech", path: :statistics_ai_trends_path },
    { actions: %w[funding_by_category], title: "Funding by Category", path: :statistics_funding_by_category_path },
    { actions: %w[funding_by_region], title: "Funding by Region", path: :statistics_funding_by_region_path },
    { actions: %w[business_model], title: "Revenue Model Insights", path: :statistics_business_model_path }
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

      {
        region: region,
        companies: region_totals[:companies],
        total_funding: region_totals[:total_funding],
        avg_funding: avg_funding,
        countries: country_rows
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
end
