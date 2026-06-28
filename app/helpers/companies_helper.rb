module CompaniesHelper
  def company_filter_category_ids
    Array(params[:category]).map(&:presence).compact.map(&:to_i)
  end

  def company_filter_statuses
    Array(params[:status]).map { |status| status.to_s.strip.downcase }.reject(&:blank?)
  end

  def company_filter_category_label(category_counts, selected_ids)
    return "All categories" if selected_ids.empty?
    return category_counts.find { |category| category[:id].to_i == selected_ids.first }&.dig(:name) || "1 category" if selected_ids.size == 1

    "#{selected_ids.size} categories"
  end

  def company_filter_status_label(status_counts, selected_statuses)
    return "Any status" if selected_statuses.empty?
    return selected_statuses.first.humanize if selected_statuses.size == 1

    "#{selected_statuses.size} statuses"
  end

  def company_filter_location_label(country, city)
    if country.present? && city.present?
      "#{city}, #{country}"
    elsif country.present?
      country
    elsif city.present?
      city
    else
      "Location"
    end
  end

  def company_filter_category_checked?(category_id, selected_ids)
    selected_ids.empty? || selected_ids.include?(category_id.to_i)
  end

  def company_filter_status_checked?(status, selected_statuses)
    selected_statuses.empty? || selected_statuses.include?(status)
  end

  def company_filter_master_checked?(selected_values, total_count)
    selected_values.empty? || selected_values.size >= total_count
  end

  def company_filter_master_indeterminate?(selected_values, total_count)
    selected_values.any? && selected_values.size < total_count
  end

  def companies_nav_context_params
    context = {}
    context[:query] = params[:query] if params[:query].present?
    context[:sort] = params[:sort].presence || "founded_desc"
    selected_categories = company_filter_category_ids
    context[:category] = selected_categories if selected_categories.any?
    selected_statuses = company_filter_statuses
    context[:status] = selected_statuses if selected_statuses.any?
    context[:country] = params[:country] if params[:country].present?
    context[:city] = params[:city] if params[:city].present?
    context[:location] = params[:location] if params[:location].present?
    context
  end

  def company_neighbor_path(neighbor, nav_context)
    company_path(neighbor[:id], nav_context)
  end

  def tag_links(tags)
    return '' if tags.blank?
    
    tags.split(',').map do |tag|
      tag = tag.strip
      next if tag.blank?
      link_to(tag, companies_path(tag: tag), class: 'tag-link')
    end.compact.join(' ').html_safe
  end

  US_STATE_CODES = %w[
    AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT
    NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY DC
  ].freeze

  COUNTRY_ISO_CODES = {
    'afghanistan' => 'AF', 'albania' => 'AL', 'algeria' => 'DZ', 'argentina' => 'AR', 'armenia' => 'AM',
    'australia' => 'AU', 'austria' => 'AT', 'azerbaijan' => 'AZ', 'bahrain' => 'BH', 'bangladesh' => 'BD',
    'belarus' => 'BY', 'belgium' => 'BE', 'bolivia' => 'BO', 'bosnia and herzegovina' => 'BA', 'brazil' => 'BR',
    'bulgaria' => 'BG', 'cambodia' => 'KH', 'cameroon' => 'CM', 'canada' => 'CA', 'chile' => 'CL',
    'china' => 'CN', 'colombia' => 'CO', 'costa rica' => 'CR', 'croatia' => 'HR', 'cyprus' => 'CY',
    'czech republic' => 'CZ', 'czechia' => 'CZ', 'denmark' => 'DK', 'dominican republic' => 'DO',
    'ecuador' => 'EC', 'egypt' => 'EG', 'el salvador' => 'SV', 'estonia' => 'EE', 'ethiopia' => 'ET',
    'finland' => 'FI', 'france' => 'FR', 'georgia' => 'GE', 'germany' => 'DE', 'ghana' => 'GH',
    'greece' => 'GR', 'guatemala' => 'GT', 'hong kong' => 'HK', 'hungary' => 'HU', 'iceland' => 'IS',
    'india' => 'IN', 'indonesia' => 'ID', 'iran' => 'IR', 'iraq' => 'IQ', 'ireland' => 'IE',
    'israel' => 'IL', 'italy' => 'IT', 'jamaica' => 'JM', 'japan' => 'JP', 'jordan' => 'JO',
    'kazakhstan' => 'KZ', 'kenya' => 'KE', 'kuwait' => 'KW', 'latvia' => 'LV', 'lebanon' => 'LB',
    'lithuania' => 'LT', 'luxembourg' => 'LU', 'malaysia' => 'MY', 'malta' => 'MT', 'mexico' => 'MX',
    'moldova' => 'MD', 'mongolia' => 'MN', 'montenegro' => 'ME', 'morocco' => 'MA', 'myanmar' => 'MM',
    'nepal' => 'NP', 'netherlands' => 'NL', 'new zealand' => 'NZ', 'nigeria' => 'NG', 'north macedonia' => 'MK',
    'norway' => 'NO', 'oman' => 'OM', 'pakistan' => 'PK', 'panama' => 'PA', 'paraguay' => 'PY',
    'peru' => 'PE', 'philippines' => 'PH', 'poland' => 'PL', 'portugal' => 'PT', 'puerto rico' => 'PR',
    'qatar' => 'QA', 'romania' => 'RO', 'russia' => 'RU', 'russian federation' => 'RU', 'rwanda' => 'RW',
    'saudi arabia' => 'SA', 'serbia' => 'RS', 'singapore' => 'SG', 'slovakia' => 'SK', 'slovenia' => 'SI',
    'south africa' => 'ZA', 'south korea' => 'KR', 'korea' => 'KR', 'spain' => 'ES', 'sri lanka' => 'LK',
    'sweden' => 'SE', 'switzerland' => 'CH', 'taiwan' => 'TW', 'tanzania' => 'TZ', 'thailand' => 'TH',
    'tunisia' => 'TN', 'turkey' => 'TR', 'türkiye' => 'TR', 'uganda' => 'UG', 'ukraine' => 'UA',
    'united arab emirates' => 'AE', 'uae' => 'AE', 'united kingdom' => 'GB', 'uk' => 'GB', 'england' => 'GB',
    'scotland' => 'GB', 'wales' => 'GB', 'northern ireland' => 'GB', 'great britain' => 'GB', 'britain' => 'GB',
    'united states' => 'US', 'united states of america' => 'US', 'usa' => 'US', 'us' => 'US', 'u.s.' => 'US',
    'u.s.a.' => 'US', 'uruguay' => 'UY', 'uzbekistan' => 'UZ', 'venezuela' => 'VE', 'vietnam' => 'VN',
    'viet nam' => 'VN', 'zimbabwe' => 'ZW', 'holland' => 'NL', 'the netherlands' => 'NL', 'republic of ireland' => 'IE',
    'brasil' => 'BR', 'deutschland' => 'DE', 'españa' => 'ES', 'espana' => 'ES', 'suisse' => 'CH', 'schweiz' => 'CH',
    'ivory coast' => 'CI', "cote d'ivoire" => 'CI', 'channel islands' => 'GB',
    'cayman islands' => 'KY', 'trinidad and tobago' => 'TT',
    'honduras' => 'HN', 'seychelles' => 'SC', 'zambia' => 'ZM', 'liechtenstein' => 'LI'
  }.freeze

  def format_location(location)
    location.to_s.gsub(/\bUnited States\b/i, "USA")
  end

  def company_display_location(company)
    format_location(company.display_location)
  end

  def company_country_iso_code(company)
    if company.country.present?
      LocationCountryResolver.country_iso_code(company.country)
    else
      location_country_iso_code(company.location)
    end
  end

  def format_company_location_with_flag(company)
    formatted = company_display_location(company)
    return formatted if formatted.blank?

    flag = country_flag_emoji(company_country_iso_code(company))
    flag.present? ? "#{flag} #{formatted}" : formatted
  end

  def format_location_with_flag(location)
    formatted = format_location(location)
    return formatted if formatted.blank?

    flag = country_flag_emoji(location_country_iso_code(location))
    flag.present? ? "#{flag} #{formatted}" : formatted
  end

  def location_country_iso_code(location)
    LocationCountryResolver.iso_code_for(location)
  end

  def country_flag_emoji(iso_code)
    code = iso_code.to_s.upcase
    return if code.blank? || !code.match?(/\A[A-Z]{2}\z/)

    code.chars.map { |char| (char.ord + 127397).chr(Encoding::UTF_8) }.join
  end

  def normalize_country_token(value)
    value.to_s.strip.downcase.gsub(/\Athe\s+/, '').gsub(/\./, '')
  end

  private :normalize_country_token

  def website_display_label(url)
    value = url.to_s.strip
    return if value.blank? || value == "n/a"

    value.sub(%r{\Ahttps?://}i, "").split("/").first.to_s
  end

  def company_inactive?(company)
    company.status.to_s.downcase.in?(%w[inactive closed])
  end

  INACTIVE_COMPANY_TOOLTIP = "This company is no longer active".freeze

  def company_legaltech_atlas_reference(company)
    url = company.legaltech_atlas_url.to_s.strip
    return nil if url.blank?
    return nil unless url.match?(%r{\Ahttps://legaltechatlas\.com/companies/[a-z0-9-]+\z})

    { label: "LegalTech Atlas", icon: "fa-solid fa-map", icon_color: "#8c1515", url: url, host: "legaltechatlas.com" }
  end

  def related_company_list(company)
    tag_ids = company.tags.map(&:id)
    return yield([]) if tag_ids.empty?

    related_companies = Company.publicly_visible
                               .joins(:tags)
                               .includes(:tags, :category, :secondary_category)
                               .where(tags: { id: tag_ids })
                               .where.not(id: company.id)
                               .distinct
                               .order(:name)
                               .limit(5)

    yield(related_companies.to_a)
  end
  
end
