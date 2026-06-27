module CacheKeyVersions
  extend ActiveSupport::Concern

  def company_cache_version
    @company_cache_version ||= Company.maximum(:updated_at)&.to_i
  end

  def category_cache_version
    @category_cache_version ||= Category.maximum(:updated_at)&.to_i
  end
end
