require "test_helper"

class PaginationHelperTest < ActionView::TestCase
  include PaginationHelper

  test "pagination_range returns zeroed range for empty collections" do
    collection = Kaminari.paginate_array([]).page(1).per(25)

    assert_equal({ start: 0, end: 0, total: 0 }, pagination_range(collection))
  end

  test "pagination_range returns current page bounds" do
    collection = Kaminari.paginate_array((1..30).to_a).page(2).per(25)

    assert_equal({ start: 26, end: 30, total: 30 }, pagination_range(collection))
  end

  test "paginated_collection? is false for single page results" do
    collection = Kaminari.paginate_array((1..2).to_a).page(1).per(25)

    assert_not paginated_collection?(collection)
  end

  test "paginated_collection? is true for multi page results" do
    collection = Kaminari.paginate_array((1..30).to_a).page(1).per(25)

    assert paginated_collection?(collection)
  end

  test "show_pagination_footer? is false for empty collections" do
    collection = Kaminari.paginate_array([]).page(1).per(25)

    assert_not show_pagination_footer?(collection)
  end

  test "show_pagination_footer? is true for single page results" do
    collection = Kaminari.paginate_array((1..2).to_a).page(1).per(25)

    assert show_pagination_footer?(collection)
  end
end
