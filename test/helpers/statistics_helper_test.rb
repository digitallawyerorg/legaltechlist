require "test_helper"

class StatisticsHelperTest < ActiveSupport::TestCase
  include Rails.application.routes.url_helpers
  def neighbors_for(action_name, params: {})
    context = Class.new do
      include StatisticsHelper
      include Rails.application.routes.url_helpers

      define_method(:action_name) { action_name }
      define_method(:params) { params }
    end

    context.new.stats_chart_neighbors
  end

  test "stats_chart_neighbors returns wrapped prev and next for funding by category" do
    neighbors = neighbors_for("funding_by_category")

    assert_equal "Target Audience", neighbors[:prev][:title]
    assert_equal statistics_target_client_path, neighbors[:prev][:path]
    assert_equal "Funding by Region", neighbors[:next][:title]
    assert_equal statistics_funding_by_region_path, neighbors[:next][:path]
  end

  test "stats_chart_neighbors returns wrapped prev and next for funding by region" do
    context = Class.new do
      include StatisticsHelper
      include Rails.application.routes.url_helpers

      define_method(:action_name) { "funding_by_category" }
      define_method(:params) { { dimension: "region" } }
    end

    neighbors = context.new.stats_chart_neighbors

    assert_equal "Funding by Category", neighbors[:prev][:title]
    assert_equal statistics_funding_by_category_path, neighbors[:prev][:path]
    assert_equal "AI in Legal Tech", neighbors[:next][:title]
    assert_equal statistics_ai_trends_path, neighbors[:next][:path]
  end

  test "stats_chart_neighbors returns wrapped prev and next for ecosystem growth" do
    neighbors = neighbors_for("total_companies")

    assert_equal "Data Coverage", neighbors[:prev][:title]
    assert_equal statistics_data_coverage_path, neighbors[:prev][:path]
    assert_equal "Geographic Distribution", neighbors[:next][:title]
    assert_equal statistics_country_distribution_path, neighbors[:next][:path]
  end

  test "stats_chart_neighbors wraps around for data coverage" do
    neighbors = neighbors_for("data_coverage")

    assert_equal "Technology Themes", neighbors[:prev][:title]
    assert_equal statistics_tag_distribution_path, neighbors[:prev][:path]
    assert_equal "Total Companies", neighbors[:next][:title]
    assert_equal statistics_total_companies_path, neighbors[:next][:path]
  end

  test "canonical_venture_stage_name maps aliases and unknown values" do
    helper = Class.new { include StatisticsHelper }.new

    assert_equal "Operating", helper.canonical_venture_stage_name("For Profit")
    assert_equal "Seed", helper.canonical_venture_stage_name("Seed")
    assert_equal "Unclassified", helper.canonical_venture_stage_name("")
    assert_equal "Unclassified", helper.canonical_venture_stage_name("Series A")
  end

  test "stats_chart_neighbors returns nil for non chart pages" do
    assert_nil neighbors_for("statistics")
  end

  test "region_country_sankey_data aggregates top countries and other bucket" do
    helper = Class.new { include StatisticsHelper }.new
    metrics = {
      "European Union" => {
        "Germany" => { companies: 40, total_funding: 0, funded_companies: 0 },
        "France" => { companies: 30, total_funding: 0, funded_companies: 0 },
        "Spain" => { companies: 20, total_funding: 0, funded_companies: 0 },
        "Italy" => { companies: 10, total_funding: 0, funded_companies: 0 },
        "Netherlands" => { companies: 8, total_funding: 0, funded_companies: 0 },
        "Belgium" => { companies: 6, total_funding: 0, funded_companies: 0 },
        "Portugal" => { companies: 4, total_funding: 0, funded_companies: 0 }
      }
    }

    sankey = helper.region_country_sankey_data(metrics, top_countries: 5)

    assert_equal 118, sankey[:total]
    assert sankey[:links].any? { |link| link[:target] == "Other (European Union)" && link[:value] == 10 }
    assert sankey[:links].any? { |link| link[:source] == "All companies" && link[:target] == "European Union" && link[:value] == 118 }
  end

  test "region_country_sunburst_tree builds hierarchical chart data" do
    helper = Class.new { include StatisticsHelper }.new
    metrics = {
      "United States" => {
        "United States" => { companies: 100, total_funding: 0, funded_companies: 0 },
        "Canada" => { companies: 5, total_funding: 0, funded_companies: 0 }
      },
      "European Union" => {
        "Germany" => { companies: 40, total_funding: 0, funded_companies: 0 }
      }
    }

    tree = helper.region_country_sunburst_tree(metrics)

    assert_equal "All companies", tree[:name]
    assert_equal 2, tree[:children].size
    us_region = tree[:children].find { |node| node[:name] == "United States" }
    assert_equal 2, us_region[:children].size
    assert_equal({ name: "United States (country)", value: 100 }, us_region[:children].find { |node| node[:name] == "United States (country)" })
    assert_equal({ name: "Canada", value: 5 }, us_region[:children].find { |node| node[:name] == "Canada" })
  end

  test "region_country_sunburst_tree supports funding values" do
    helper = Class.new { include StatisticsHelper }.new
    metrics = {
      "United States" => {
        "United States" => { companies: 10, total_funding: BigDecimal("500000.0"), funded_companies: 5 }
      }
    }

    tree = helper.region_country_sunburst_tree(metrics, root: StatisticsHelper::REGION_COUNTRY_FUNDING_ROOT, value_key: :total_funding)

    assert_equal "Disclosed funding", tree[:name]
    assert_equal 500_000.0, tree[:children].first[:children].first[:value]
    assert_includes tree.to_json, '"value":500000.0'
    assert_not_includes tree.to_json, '"value":"500000'
  end

  test "build_funding_region_table_data sorts by total funding" do
    helper = Class.new { include StatisticsHelper }.new
    metrics = {
      "Canada" => {
        "Canada" => { companies: 10, total_funding: 1000, funded_companies: 2 }
      },
      "United States" => {
        "United States" => { companies: 5, total_funding: 5000, funded_companies: 3 }
      }
    }

    table_data = helper.build_funding_region_table_data(metrics)

    assert_equal "United States", table_data.first[:region]
  end

  test "build_region_table_data aggregates region totals" do
    helper = Class.new { include StatisticsHelper }.new
    metrics = {
      "Canada" => {
        "Canada" => { companies: 10, total_funding: 1000, funded_companies: 2 }
      }
    }

    table_data = helper.build_region_table_data(metrics)

    assert_equal 1, table_data.size
    assert_equal "Canada", table_data.first[:region]
    assert_equal "Canada", table_data.first[:country_label]
    assert_equal 10, table_data.first[:companies]
    assert_empty table_data.first[:countries]
  end

  test "build_region_table_data keeps country sub-rows for multi-country regions" do
    helper = Class.new { include StatisticsHelper }.new
    metrics = {
      "Europe" => {
        "Germany" => { companies: 40, total_funding: 0, funded_companies: 0 },
        "France" => { companies: 30, total_funding: 0, funded_companies: 0 }
      }
    }

    table_data = helper.build_region_table_data(metrics)

    assert_nil table_data.first[:country_label]
    assert_equal 2, table_data.first[:countries].size
  end

  test "stats_region_distribution_preview returns top regions and rest of world" do
    helper = Class.new { include StatisticsHelper }.new
    preview = helper.stats_region_distribution_preview

    assert preview.any?
    assert preview.size <= 4
    assert_equal "Rest of world", preview.last[:label] if preview.size > 1
    assert_equal 100, preview.sum { |row| row[:share] }
    assert preview.all? { |row| row[:label].present? && row[:share].positive? }
    assert_equal preview.map { |row| row[:share] }, preview.map { |row| row[:share] }.sort.reverse
  end

  test "stats_compact_funding formats large amounts compactly" do
    helper = Class.new { include StatisticsHelper }.new

    assert_equal "$1.2B", helper.stats_compact_funding(1_200_000_000)
    assert_equal "$450M", helper.stats_compact_funding(450_000_000)
    assert_equal "$0", helper.stats_compact_funding(0)
  end

  test "stats index meta counts return non-negative values" do
    helper = Class.new { include StatisticsHelper }.new

    assert_operator helper.stats_index_category_count, :>=, 0
    assert_operator helper.stats_index_business_model_count, :>=, 0
    assert_operator helper.stats_index_target_market_count, :>=, 0
    assert_operator helper.stats_index_total_funding_amount, :>=, 0
    assert_operator helper.stats_index_funding_country_count, :>=, 0
    assert_operator helper.stats_index_ai_company_count, :>=, 0
    assert_operator helper.stats_index_tag_count, :>=, 0
  end

  test "stats_target_client_preview returns top segments and rest" do
    helper = Class.new { include StatisticsHelper }.new
    preview = helper.stats_target_client_preview

    assert preview.any?
    assert preview.size <= 4
    assert_equal 100, preview.sum { |row| row[:share] }
    assert preview.all? { |row| row[:label].present? && row[:share].positive? }
    assert_equal preview.map { |row| row[:share] }, preview.map { |row| row[:share] }.sort.reverse
  end

  test "stats_coverage_heatmap_dimensions lists selectable primary dimensions" do
    helper = Class.new { include StatisticsHelper }.new
    dimensions = helper.stats_coverage_heatmap_dimensions

    assert_equal %w[category business_model location target_market fundraising], dimensions.map { |dimension| dimension[:key] }
    assert_equal "Category", dimensions.first[:label]
    location = dimensions.find { |dimension| dimension[:key] == "location" }
    assert_equal "Category", location[:secondary]
  end

  test "coverage_heatmap_grid keeps region columns in order and flags gaps" do
    helper = Class.new { include StatisticsHelper }.new
    counts = {
      "Contract Management" => { "North America" => 10, "Europe" => 4 },
      "E-Discovery" => { "North America" => 2 }
    }

    grid = helper.coverage_heatmap_grid(counts, primary_label: "Category", secondary_label: "Region", column_order: StatisticsHelper::COVERAGE_HEATMAP_REGION_ORDER)

    assert_equal ["North America", "Europe"], grid[:columns]
    assert_equal "Contract Management", grid[:rows].first[:label]
    assert_equal 14, grid[:rows].first[:total]
    assert_equal [10, 4], grid[:rows].first[:cells]
    ediscovery = grid[:rows].find { |row| row[:label] == "E-Discovery" }
    assert_equal [2, 0], ediscovery[:cells]
    assert_equal 10, grid[:max]
  end

  test "coverage_heatmap_grid honors an explicit row order" do
    helper = Class.new { include StatisticsHelper }.new
    counts = {
      "Seed" => { "Europe" => 3 },
      "Operating" => { "North America" => 12 },
      "IPO" => { "North America" => 1 }
    }

    grid = helper.coverage_heatmap_grid(counts, primary_label: "Fundraising", secondary_label: "Region", column_order: StatisticsHelper::COVERAGE_HEATMAP_REGION_ORDER, row_order: StatisticsHelper::VENTURE_STAGE_ORDER)

    assert_equal %w[Operating Seed IPO], grid[:rows].map { |row| row[:label] }
  end

  test "coverage_heatmap_grid buckets overflow rows and columns into Other" do
    helper = Class.new { include StatisticsHelper }.new
    counts = {
      "Row A" => { "C1" => 5, "C2" => 4, "C3" => 3 },
      "Row B" => { "C1" => 2 },
      "Row C" => { "C3" => 1 }
    }

    grid = helper.coverage_heatmap_grid(counts, primary_label: "X", secondary_label: "Y", row_limit: 1, column_limit: 1)

    assert_equal ["C1", StatisticsHelper::COVERAGE_HEATMAP_OTHER_LABEL], grid[:columns]
    assert_equal ["Row A", StatisticsHelper::COVERAGE_HEATMAP_OTHER_LABEL], grid[:rows].map { |row| row[:label] }
    other_row = grid[:rows].last
    assert_equal 3, other_row[:total]
    assert_equal [2, 1], other_row[:cells]
  end

  test "coverage_heatmap_cell_presentation distinguishes gaps from filled cells" do
    helper = Class.new { include StatisticsHelper }.new

    gap = helper.coverage_heatmap_cell_presentation(0, 20)
    assert gap[:gap]
    assert_nil gap[:background]

    filled = helper.coverage_heatmap_cell_presentation(20, 20)
    assert_not filled[:gap]
    assert_match(/\Argb\(/, filled[:background])
    assert_equal "#ffffff", filled[:text_color]

    faint = helper.coverage_heatmap_cell_presentation(1, 200)
    assert_equal "#2a2723", faint[:text_color]
  end

  test "coverage_heatmap_scale_color interpolates and clamps ratio" do
    helper = Class.new { include StatisticsHelper }.new

    assert_equal "rgb(250, 241, 236)", helper.coverage_heatmap_scale_color(0)
    assert_equal "rgb(140, 21, 21)", helper.coverage_heatmap_scale_color(1.0)
    assert_equal "rgb(140, 21, 21)", helper.coverage_heatmap_scale_color(2.5)
  end

  test "stats_coverage_heatmap_preview returns a bounded grid" do
    helper = Class.new { include StatisticsHelper }.new
    preview = helper.stats_coverage_heatmap_preview(row_count: 3, column_count: 4)

    assert preview.key?(:columns)
    assert preview.key?(:rows)
    assert_operator preview[:columns].size, :<=, 4
    assert_operator preview[:rows].size, :<=, 3
    assert_operator preview[:max], :>=, 0
    preview[:rows].each do |row|
      assert_equal preview[:columns].size, row[:cells].size
      assert row[:cells].all? { |value| value.to_i >= 0 }
    end
  end

  test "build_coverage_heatmaps returns a grid for every dimension" do
    helper = Class.new { include StatisticsHelper }.new
    heatmaps = helper.build_coverage_heatmaps

    assert_equal %w[category business_model location target_market fundraising].sort, heatmaps.keys.sort
    heatmaps.each_value do |grid|
      assert grid.key?(:rows)
      assert grid.key?(:columns)
      assert_operator grid[:max], :>=, 0
      grid[:rows].each do |row|
        assert_equal grid[:columns].size, row[:cells].size
        assert_operator row[:total], :>=, 0
      end
    end
  end
end
