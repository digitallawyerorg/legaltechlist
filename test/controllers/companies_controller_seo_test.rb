require "test_helper"

class CompaniesControllerTest < ActionController::TestCase
  test "index includes h1 heading" do
    get :index
    assert_response :success
    assert_select "h1.company-index-title", text: "Legal Tech Companies"
  end

  test "index includes meta description" do
    get :index
    assert_response :success
    assert_select "meta[name=?][content]", "description"
  end

  test "index first page includes rel next when more pages exist" do
    create_visible_companies(24)

    get :index
    assert_response :success
    assert_select "link[rel=?]", "next", count: 1
    assert_select "link[rel=?]", "prev", count: 0
    assert_select "link[rel=?][href*=?]", "next", "page=2"
  end

  test "index second page includes rel prev without page one param" do
    create_visible_companies(24)

    get :index, params: { page: 2 }
    assert_response :success
    assert_select "link[rel=?]", "prev", count: 1
    assert_select "link[rel=?]", "next", count: 0
    assert_select "link[rel=?][href=?]", "prev", "#{SeoHelper::DEFAULT_SITE_URL}/companies"
  end

  private

  def create_visible_companies(count)
    category = categories(:one)
    business_model = business_models(:one)
    target_client = target_clients(:one)

    count.times do |i|
      Company.create!(
        name: "Pagination Co #{i}",
        location: "San Francisco, CA",
        founded_date: "2020",
        description: "A legal tech company for pagination testing.",
        category: category,
        business_model: business_model,
        target_client: target_client,
        visible: true
      )
    end
  end
end
