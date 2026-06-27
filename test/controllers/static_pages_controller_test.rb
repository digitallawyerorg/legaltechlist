require 'test_helper'

class StaticPagesControllerTest < ActionController::TestCase
  test "should get home" do
    get :home
    assert_response :success
  end

  test "should get about" do
    get :about
    assert_response :success
  end

  test "extract_country normalizes country aliases and administrative regions" do
    examples = {
      "San Francisco, CA" => "United States",
      "San Francisco,  California" => "United States",
      "London,  England" => "United Kingdom",
      "Toronto,  Ontario" => "Canada",
      "Mumbai,  Maharashtra" => "India",
      "Sydney,  New South Wales" => "Australia",
      "Tallinn,  Harjumaa" => "Estonia",
      "Milano,  Lombardia" => "Italy",
      "Roma,  Lazio" => "Italy",
      "Amsterdam,  Noord-Holland" => "Netherlands",
      "Cambridge,  Cambridgeshire" => "United Kingdom",
      "Edinburgh,  Edinburgh" => "United Kingdom",
      "Sheridan,  Wyoming" => "United States",
      "Noida,  Uttar Pradesh" => "India",
      "Ahmedabad,  Gujarat" => "India",
      "Barcelona,  Catalonia" => "Spain",
      "Singapore,  Central Region" => "Singapore",
      "Dubai,  Dubai" => "United Arab Emirates",
      "Gent,  Oost-Vlaanderen" => "Belgium",
      "Tel Aviv,  Tel Aviv" => "Israel",
      "Islamabad,  Islamabad" => "Pakistan",
      "Limasol,  Limassol" => "Cyprus",
      "Cape Town,  NA - South Africa" => "South Africa",
      "San Francisco, United States1" => "United States",
      "New York City, United States2" => "United States",
      "London, United Kingdom1" => "United Kingdom",
      "Wiesbaden, Germany1" => "Germany",
      "Taipei, Taiwan1" => "Taiwan",
      "Hong Kong China" => "Hong Kong"
    }

    examples.each do |location, country|
      assert_equal country, @controller.send(:extract_country, location), "Expected #{location.inspect} to normalize to #{country.inspect}"
    end
  end

  test "extract_country skips blank locations" do
    assert_nil @controller.send(:extract_country, nil)
    assert_nil @controller.send(:extract_country, "")
  end

end
