module ApplicationHelper
  include CacheKeyVersions

  # Visually hidden warning that a link opens in a new browser tab.
  def new_tab_note
    tag.span " (opens in new tab)", class: "visually-hidden"
  end

  # Link text plus the new-tab warning, for links that carry target="_blank".
  def new_tab_label(text)
    safe_join([text, new_tab_note])
  end

  def visible_company_count
    Rails.cache.fetch("companies/visible_count/#{company_cache_version}", expires_in: 10.minutes) do
      Company.where(visible: true).count
    end
  end

  def company_search_categories
    Rails.cache.fetch("companies/search_modal_categories/#{company_cache_version}/#{category_cache_version}", expires_in: 10.minutes) do
      counts = Category.where.not(name: "Unknown")
                       .where.not(id: [12, 13, 14])
                       .left_joins(:companies)
                       .where(companies: { visible: true })
                       .group("categories.id", "categories.name")
                       .count
      counts.map do |(category_id, name), count|
        { id: category_id, name: name, count: count, icon: category_icon(name), url: category_path(Category.find(category_id)) }
      end.sort_by { |category| -category[:count] }
    end
  end

  def category_icon(category_name)
    case category_name.downcase
    when /analytics/ then 'fa fa-chart-bar'
    when /compliance/ then 'fa fa-shield'
    when /contract/ then 'fa fa-file-contract'
    when /document/ then 'fa fa-folder'
    when /research/ then 'fa fa-book'
    when /litigation/ then 'fa fa-scale-balanced'
    when /ediscovery|e-discovery/ then 'fa fa-magnifying-glass'
    when /operations/ then 'fa fa-building'
    when /practice/ then 'fa fa-calendar-check'
    when /access to justice|public sector/ then 'fa fa-landmark'
    when /collaboration/ then 'fa fa-users'
    when /ai|emerging/ then 'fa fa-microchip'
    when /talent|people/ then 'fa fa-user-plus'
    when /marketplace/ then 'fa fa-briefcase'
    when /ip|intellectual/ then 'fa fa-lightbulb'
    when /process/ then 'fa fa-gears'
    when /dei|diversity/ then 'fa fa-users-between-lines'
    when /security/ then 'fa fa-lock'
    else 'fa fa-cube'
    end
  end

  def growth_indicator_class(rate)
    return 'text-muted' if rate.nil?

    case rate
    when 0..20
      'text-danger'
    when 20..40
      'text-warning'
    when 40..60
      'text-info'
    when 60..80
      'text-primary'
    else
      'text-success'
    end
  end

  def maturity_stage_class(stage)
    case stage
    when 'Emerging'
      'badge bg-info'
    when 'Growing'
      'badge bg-success'
    when 'Established'
      'badge bg-primary'
    when 'Mature'
      'badge bg-dark'
    else
      'badge bg-secondary'
    end
  end

  def tag_cloud(tags, classes)
    return if tags.empty?

    max = tags.max_by(&:count)
    min = tags.min_by(&:count)
    spread = max.count - min.count + 1

    tags.each do |tag|
      index = if spread == 1
        0
      else
        ((tag.count - min.count) / spread.to_f * (classes.size - 1)).round
      end
      yield(tag, classes[index])
    end
  end

  def growth_rate_class(rate)
    return 'text-muted' if rate.nil?
    if rate > 0
      'badge badge-sm bg-danger-subtle text-danger'
    elsif rate < 0
      'badge badge-sm bg-success-subtle text-success'
    else
      'text-muted'
    end
  end

  def growth_rate_content(rate)
    return 'N/A' if rate.nil?
    prefix = rate > 0 ? '+' : ''
    "#{prefix}#{rate.round(1)}%"
  end

  def nav_overview_dropdown_label
    path = request.path

    return "About" if path == about_path
    return "Methodology" if path == statistics_methodology_path
    return "Statistics" if path.start_with?("/statistics")
    return "Companies" if controller_name == "companies"

    "Overview"
  end

  def nav_overview_dropdown_item_class(label)
    ["dropdown-item", ("active" if nav_overview_dropdown_label == label)].compact.join(" ")
  end

  def required_label_text(text)
    safe_join([text, content_tag(:abbr, "*", class: "required-asterisk", title: "required")])
  end

  def admin_duplicate_match_warning(candidate)
    matches = (Array(candidate["name_matches"]) + Array(candidate["domain_matches"])).uniq { |match| match["id"] }
    return if matches.empty?

    links = matches.map do |match|
      link_to(match["name"], custom_admin_company_review_path(match["id"]))
    end
    safe_join(["Possible duplicates found: ", safe_join(links, ", ")])
  end

  # What actually agreed, and on what value.
  #
  # The duplicate panel used to print the matched record's stored canonical_domain and
  # label the line "matched on <strongest key>". Those are two unrelated facts stuck
  # together: canonical_domain is CompanyIdentityMatcher.index_row's row[:domains].first,
  # the companies.canonical_domain column, which that method's own comment notes is NOT
  # recomputed when main_url changes. On a rebranded entry it is the PREVIOUS domain, so
  # the card named a domain the match never fired on — Apertera #11445 was shown as an
  # "exact domain" match on alexatranslations.com, the domain it carried before the
  # June 2026 rename. matched_value is the value the key was actually compared on, and
  # the matcher has always carried it; this only stops throwing it away.
  #
  # Every key that agreed is listed, strongest first, the way the review-queue side of
  # the same panel already lists them. matched_value is the strongest key's value, so it
  # is attached to that key rather than to the sentence.
  def admin_duplicate_match_basis(match)
    keys = (Array(match["match_types"]).presence || [match["match_type"]]).compact_blank.map(&:to_s)
    return "" if keys.empty?

    labels = keys.map { |type| type.humanize.downcase }
    value = match["matched_value"].presence
    labels[0] = "#{labels[0]} (#{value})" if value
    "matched on #{labels.to_sentence}"
  end

  # The address the entry is listed at, shown only when it is not the value that matched.
  # Repeating the matched domain as a bare string in front of the basis is what made the
  # two readable as one claim in the first place.
  def admin_duplicate_listed_address(match)
    listed = match["canonical_domain"].presence || match["main_url"].presence
    return if listed.blank? || listed == match["matched_value"]

    "entry is listed at #{listed}"
  end

  # Re-submit the originating queue's filters with a form, so completing a record
  # returns the reviewer to the list they were working through. See ReviewQueueContext.
  def queue_hidden_fields(queue)
    safe_join(Array(queue).map { |key, value| hidden_field_tag("queue[#{key}]", value, id: nil) })
  end
end
