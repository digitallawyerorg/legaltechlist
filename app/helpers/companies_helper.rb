module CompaniesHelper
  def tag_links(tags)
    return '' if tags.blank?
    
    tags.split(',').map do |tag|
      tag = tag.strip
      next if tag.blank?
      link_to(tag, companies_path(tag: tag), class: 'tag-link')
    end.compact.join(' ').html_safe
  end
  
  def tag_cloud(tags, classes)
    max = tags.sort_by(&:count).last
    tags.each do |tag|
      index = tag.count.to_f / max.count * (classes.size - 1)
      yield(tag, classes[index.round])
    end
  end
  
  def related_company_list(company)
    tag_ids = company.tags.map(&:id)
    return yield([]) if tag_ids.empty?

    related_companies = Company.publicly_visible
                               .joins(:tags)
                               .includes(:tags)
                               .where(tags: { id: tag_ids })
                               .where.not(id: company.id)
                               .distinct
                               .order(:name)
                               .limit(5)

    yield(related_companies.to_a)
  end
  
end
