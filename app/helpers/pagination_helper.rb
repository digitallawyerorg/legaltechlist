module PaginationHelper
  def pagination_range(collection)
    total = collection.respond_to?(:total_count) ? collection.total_count : collection.size

    if collection.blank?
      { start: 0, end: 0, total: total }
    else
      {
        start: collection.offset_value + 1,
        end: collection.offset_value + collection.length,
        total: total
      }
    end
  end

  def paginated_collection?(collection)
    collection.respond_to?(:total_pages) && collection.total_pages > 1
  end

  def show_pagination_footer?(collection)
    return false unless collection.respond_to?(:total_count)

    collection.total_count.positive? || paginated_collection?(collection)
  end
end
