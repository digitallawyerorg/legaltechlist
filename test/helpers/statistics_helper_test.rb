require "test_helper"

class StatisticsHelperTest < ActiveSupport::TestCase
  include Rails.application.routes.url_helpers
  def neighbors_for(action_name)
    context = Class.new do
      include StatisticsHelper
      include Rails.application.routes.url_helpers

      define_method(:action_name) { action_name }
    end

    context.new.stats_chart_neighbors
  end

  test "stats_chart_neighbors returns wrapped prev and next for funding" do
    neighbors = neighbors_for("funding_by_category")

    assert_equal "Industry Focus", neighbors[:prev][:title]
    assert_equal statistics_category_evolution_5_years_path, neighbors[:prev][:path]
    assert_equal "AI in Legal Tech", neighbors[:next][:title]
    assert_equal statistics_ai_trends_path, neighbors[:next][:path]
  end

  test "stats_chart_neighbors returns wrapped prev and next for ecosystem growth" do
    neighbors = neighbors_for("total_companies")

    assert_equal "Technology Themes", neighbors[:prev][:title]
    assert_equal statistics_tag_distribution_path, neighbors[:prev][:path]
    assert_equal "Geographic Distribution", neighbors[:next][:title]
    assert_equal statistics_country_distribution_path, neighbors[:next][:path]
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

  test "stats_target_client_preview returns top segments and rest" do
    helper = Class.new { include StatisticsHelper }.new
    preview = helper.stats_target_client_preview

    assert preview.any?
    assert preview.size <= 4
    assert_equal 100, preview.sum { |row| row[:share] }
    assert preview.all? { |row| row[:label].present? && row[:share].positive? }
    assert_equal preview.map { |row| row[:share] }, preview.map { |row| row[:share] }.sort.reverse
  end
end
