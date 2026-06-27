class LocationCountryResolver
  US_STATE_CODES = %w[
    AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT
    NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY DC
  ].freeze

  COUNTRY_ALIASES = {
    "USA" => "United States",
    "United States" => "United States",
    "US" => "United States",
    "U.S." => "United States",
    "U.S.A." => "United States",
    "UK" => "United Kingdom",
    "United Kingdom" => "United Kingdom",
    "Great Britain" => "United Kingdom",
    "England" => "United Kingdom",
    "Scotland" => "United Kingdom",
    "Wales" => "United Kingdom",
    "Northern Ireland" => "United Kingdom",
    "UAE" => "United Arab Emirates",
    "U.A.E." => "United Arab Emirates",
    "The Netherlands" => "Netherlands",
    "Russian Federation" => "Russia",
    "Slovakia Slovak Republic" => "Slovakia",
    "Hong Kong China" => "Hong Kong",
    "Germany" => "Germany",
    "Hong Kong" => "Hong Kong",
    "South Africa" => "South Africa",
    "Taiwan" => "Taiwan",
    "Uruguay" => "Uruguay",
    "Venezuela" => "Venezuela",
    "Vietnam" => "Vietnam",
    "NA - South Africa" => "South Africa",
    "NA - Uruguay" => "Uruguay",
    "NA - Venezuela" => "Venezuela",
    "NA - Vietnam" => "Vietnam",
    "Ivory Coast" => "Côte d'Ivoire",
    "Channel Islands" => "United Kingdom"
  }.freeze

  ADMINISTRATIVE_REGION_COUNTRIES = {
    "CA" => "United States",
    "Alabama" => "United States", "Alaska" => "United States", "Arizona" => "United States",
    "Arkansas" => "United States", "California" => "United States", "Colorado" => "United States",
    "Connecticut" => "United States", "Delaware" => "United States", "District of Columbia" => "United States",
    "Florida" => "United States", "Georgia" => "United States", "Hawaii" => "United States",
    "Idaho" => "United States", "Illinois" => "United States", "Indiana" => "United States",
    "Iowa" => "United States", "Kansas" => "United States", "Kentucky" => "United States",
    "Louisiana" => "United States", "Maine" => "United States", "Maryland" => "United States",
    "Massachusetts" => "United States", "Michigan" => "United States", "Minnesota" => "United States",
    "Mississippi" => "United States", "Missouri" => "United States", "Montana" => "United States",
    "Nebraska" => "United States", "Nevada" => "United States", "New Hampshire" => "United States",
    "New Jersey" => "United States", "New Mexico" => "United States", "New York" => "United States",
    "North Carolina" => "United States", "North Dakota" => "United States", "Ohio" => "United States",
    "Oklahoma" => "United States", "Oregon" => "United States", "Pennsylvania" => "United States",
    "Rhode Island" => "United States", "South Carolina" => "United States", "South Dakota" => "United States",
    "Tennessee" => "United States", "Texas" => "United States", "Utah" => "United States",
    "Vermont" => "United States", "Virginia" => "United States", "Washington" => "United States",
    "West Virginia" => "United States", "Wisconsin" => "United States", "Wyoming" => "United States",
    "Alberta" => "Canada", "British Columbia" => "Canada", "Manitoba" => "Canada",
    "New Brunswick" => "Canada", "Newfoundland and Labrador" => "Canada", "Nova Scotia" => "Canada",
    "Ontario" => "Canada", "Prince Edward Island" => "Canada", "Quebec" => "Canada",
    "Saskatchewan" => "Canada",
    "Andhra Pradesh" => "India", "Assam" => "India", "Bihar" => "India", "Chandigarh" => "India",
    "Delhi" => "India", "Haryana" => "India", "Karnataka" => "India", "Kerala" => "India",
    "Madhya Pradesh" => "India", "Maharashtra" => "India", "Orissa" => "India", "Punjab" => "India",
    "Rajasthan" => "India", "Tamil Nadu" => "India", "Telangana" => "India", "Uttar Pradesh" => "India",
    "West Bengal" => "India", "Gujarat" => "India",
    "New South Wales" => "Australia", "South Australia" => "Australia", "Victoria" => "Australia",
    "Queensland" => "Australia", "Western Australia" => "Australia",
    "Auckland" => "New Zealand", "Christchurch 8011" => "New Zealand", "Wellington" => "New Zealand",
    "Berlin" => "Germany", "Bayern" => "Germany", "Baden-Wurttemberg" => "Germany",
    "Hamburg" => "Germany", "Niedersachsen" => "Germany", "Nordrhein-Westfalen" => "Germany",
    "Noord-Holland" => "Netherlands", "Limburg" => "Netherlands", "Utrecht" => "Netherlands",
    "Flevoland" => "Netherlands", "Zuid-Holland" => "Netherlands",
    "Lombardia" => "Italy", "Liguria" => "Italy", "Lazio" => "Italy", "Marche" => "Italy",
    "Piemonte" => "Italy", "Sicilia" => "Italy", "Veneto" => "Italy", "Toscana" => "Italy",
    "Andalucia" => "Spain", "Andalusia" => "Spain", "Catalonia" => "Spain", "Galicia" => "Spain",
    "Madrid" => "Spain", "Comunidad Valenciana" => "Spain", "Basque Country" => "Spain",
    "Region Metropolitana" => "Chile", "Sao Paulo" => "Brazil", "Lisboa" => "Portugal",
    "Bucuresti" => "Romania", "Ile-de-France" => "France", "Poitou-Charentes" => "France",
    "Rhone-Alpes" => "France", "Mazowieckie" => "Poland", "Harjumaa" => "Estonia",
    "Vorumaa" => "Estonia", "Dublin" => "Ireland", "Cork" => "Ireland", "Wexford" => "Ireland",
    "Skane Lan" => "Sweden", "Stockholms Lan" => "Sweden", "Vastra Gotaland" => "Sweden",
    "Schwyz" => "Switzerland", "Vaud" => "Switzerland", "Zurich" => "Switzerland",
    "Federal Capital Territory" => "Nigeria", "Lagos" => "Nigeria", "Al Jizah" => "Egypt",
    "Al Kuwayt" => "Kuwait", "Ar Riyad" => "Saudi Arabia", "Makkah" => "Saudi Arabia",
    "Ankara" => "Turkey", "Istanbul" => "Turkey", "Jalisco" => "Mexico", "Quintana Roo" => "Mexico",
    "Jakarta Raya" => "Indonesia", "Jawa Barat" => "Indonesia", "Chiba" => "Japan", "Tokyo" => "Japan",
    "Pusan-jikhalsi" => "South Korea", "Oost-Vlaanderen" => "Belgium", "Vlaams-Brabant" => "Belgium",
    "Brussels" => "Belgium", "Antwerpen" => "Belgium", "Central Region" => "Singapore",
    "Tel Aviv" => "Israel", "Islamabad" => "Pakistan", "Limassol" => "Cyprus",
    "Dubai" => "United Arab Emirates", "Abu Dhabi" => "United Arab Emirates",
    "Macedonia" => "North Macedonia", "Dallas" => "United States",
    "Hlavni mesto Praha" => "Czech Republic", "L'vivs'ka Oblast'" => "Ukraine",
    "Ljubljana Urban Commune" => "Slovenia", "Vilniaus Apskritis" => "Lithuania",
    "Vojvodina" => "Serbia", "Cesu" => "Latvia", "Grand Casablanca" => "Morocco",
    "San Jose" => "Costa Rica", "Tacloban" => "Philippines", "Manila" => "Philippines", "Lima" => "Peru"
  }.freeze

  # Well-known cities that resolve unambiguously when given without a country.
  # Case-insensitive lookup via city_country_for.
  CITY_COUNTRIES = {
    "London" => "United Kingdom",
    "Paris" => "France",
    "Berlin" => "Germany",
    "Amsterdam" => "Netherlands",
    "Vienna" => "Austria",
    "Copenhagen" => "Denmark",
    "Stockholm" => "Sweden",
    "Oslo" => "Norway",
    "Helsinki" => "Finland",
    "Dublin" => "Ireland",
    "Brussels" => "Belgium",
    "Madrid" => "Spain",
    "Barcelona" => "Spain",
    "Lisbon" => "Portugal",
    "Rome" => "Italy",
    "Milan" => "Italy",
    "Zurich" => "Switzerland",
    "Basel" => "Switzerland",
    "Geneva" => "Switzerland",
    "Munich" => "Germany",
    "Frankfurt" => "Germany",
    "Frankfurt am Main" => "Germany",
    "Hamburg" => "Germany",
    "Mannheim" => "Germany",
    "Eindhoven" => "Netherlands",
    "Leuven" => "Belgium",
    "Tallinn" => "Estonia",
    "Bordeaux" => "France",
    "Bilbao" => "Spain",
    "Valencia" => "Spain",
    "Edinburgh" => "United Kingdom",
    "Manchester" => "United Kingdom",
    "Birmingham" => "United Kingdom",
    "Bristol" => "United Kingdom",
    "Leeds" => "United Kingdom",
    "Liverpool" => "United Kingdom",
    "Glasgow" => "United Kingdom",
    "Cardiff" => "United Kingdom",
    "Oxford" => "United Kingdom",
    "Cambridge" => "United Kingdom",
    "Nottingham" => "United Kingdom",
    "Swansea" => "United Kingdom",
    "Los Angeles" => "United States",
    "San Francisco" => "United States",
    "Chicago" => "United States",
    "New York" => "United States",
    "NYC" => "United States",
    "Boston" => "United States",
    "Seattle" => "United States",
    "Austin" => "United States",
    "Denver" => "United States",
    "Houston" => "United States",
    "Atlanta" => "United States",
    "Philadelphia" => "United States",
    "Minneapolis" => "United States",
    "Sacramento" => "United States",
    "Charlotte" => "United States",
    "Indianapolis" => "United States",
    "Baltimore" => "United States",
    "Pittsburgh" => "United States",
    "Salt Lake City" => "United States",
    "Princeton" => "United States",
    "Fremont" => "United States",
    "Cupertino" => "United States",
    "Irvine" => "United States",
    "Eugene" => "United States",
    "Lubbock" => "United States",
    "Miami" => "United States",
    "Dallas" => "United States",
    "Phoenix" => "United States",
    "Portland" => "United States",
    "San Diego" => "United States",
    "San Jose" => "United States",
    "Washington" => "United States",
    "Detroit" => "United States",
    "Nashville" => "United States",
    "Raleigh" => "United States",
    "Tampa" => "United States",
    "Orlando" => "United States",
    "Saint Louis" => "United States",
    "St Louis" => "United States",
    "Kansas City" => "United States",
    "New Orleans" => "United States",
    "Jersey City" => "United States",
    "East Brunswick" => "United States",
    "West Sacramento" => "United States",
    "Pleasanton" => "United States",
    "Irving" => "United States",
    "West Palm Beach" => "United States",
    "Pompano Beach" => "United States",
    "Livermore" => "United States",
    "Delaware City" => "United States",
    "Studio City" => "United States",
    "Lexington" => "United States",
    "Toronto" => "Canada",
    "Vancouver" => "Canada",
    "Montreal" => "Canada",
    "Ottawa" => "Canada",
    "Edmonton" => "Canada",
    "Calgary" => "Canada",
    "Sydney" => "Australia",
    "Melbourne" => "Australia",
    "Brisbane" => "Australia",
    "Adelaide" => "Australia",
    "Perth" => "Australia",
    "Mumbai" => "India",
    "Bengaluru" => "India",
    "Bangalore" => "India",
    "Hyderabad" => "India",
    "Chennai" => "India",
    "Gurgaon" => "India",
    "Jaipur" => "India",
    "Jalandhar" => "India",
    "Kolkata" => "India",
    "Airoli" => "India",
    "Delhi" => "India",
    "New Delhi" => "India",
    "Pune" => "India",
    "Nairobi" => "Kenya",
    "Singapore" => "Singapore",
    "Hong Kong" => "Hong Kong",
    "Tokyo" => "Japan",
    "Seoul" => "South Korea",
    "Beijing" => "China",
    "Shanghai" => "China",
    "Mexico City" => "Mexico",
    "Guadalajara" => "Mexico",
    "Buenos Aires" => "Argentina",
    "São Paulo" => "Brazil",
    "Sao Paulo" => "Brazil",
    "Curitiba" => "Brazil",
    "Rio de Janeiro" => "Brazil",
    "Bogota" => "Colombia",
    "Bogotá" => "Colombia",
    "Santiago" => "Chile",
    "Lima" => "Peru",
    "Dubai" => "United Arab Emirates",
    "Abu Dhabi" => "United Arab Emirates",
    "Tel Aviv" => "Israel",
    "Istanbul" => "Turkey",
    "Johannesburg" => "South Africa",
    "Cape Town" => "South Africa",
    "Herentals" => "Belgium",
    "Helsingborg" => "Sweden",
    "Depok City" => "Indonesia",
    "Jakarta" => "Indonesia"
  }.freeze

  # Exact malformed location strings that should map to a normalized "City, Country" value.
  LOCATION_OVERRIDES = {
    "Toronto CANADA" => "Toronto, Canada",
    "Zurich Switzerland" => "Zurich, Switzerland",
    "Kolkata India" => "Kolkata, India",
    "Accra Ghana" => "Accra, Ghana",
    "Exeter England" => "Exeter, United Kingdom",
    "Zaragoza Spain" => "Zaragoza, Spain",
    "Gurgaon Haryana" => "Gurgaon, India",
    "Washington DC USA" => "Washington, United States",
    "Bellevue WA" => "Bellevue, United States",
    "BELLEVUE" => "Bellevue, United States",
    "Denver CO" => "Denver, United States",
    "Buffalo NY" => "Buffalo, United States",
    "Sheikh Zayed Road Dubai" => "Dubai, United Arab Emirates",
    "Paris 75001" => "Paris, France",
    "TallinnEstonia" => "Tallinn, Estonia",
    "PunjabIndia" => "Punjab, India",
    "United States California" => "California, United States"
  }.freeze

  UK_ADMINISTRATIVE_AREAS = [
    "Aberdeen City", "Barking and Dagenham", "Bath and North East Somerset", "Belfast", "Birmingham",
    "Brighton and Hove", "Bristol", "Buckinghamshire", "Caerphilly", "Cambridgeshire", "Cardiff",
    "Cheshire", "Cheshire East", "Cornwall", "Coventry", "Derby", "Dorset", "East Sussex", "Edinburgh",
    "Essex", "Fermanagh", "Glasgow City", "Hampshire", "Harrow", "Havering", "Herefordshire", "Hertford",
    "Hillingdon", "Kent", "Kingston upon Hull", "Kirklees", "Lancashire", "Leeds", "Liverpool",
    "Manchester", "Middlesbrough", "Milton Keynes", "Newcastle upon Tyne", "Newport", "Norfolk",
    "North Ayrshire", "North Lincolnshire", "North Yorkshire", "Northamptonshire", "Nottingham",
    "Oxfordshire", "Reading", "Redbridge", "Richmond upon Thames", "Rochdale", "Solihull", "Somerset",
    "South Lanarkshire", "South Tyneside", "Southampton", "Staffordshire", "Stirling", "Stockport",
    "Stockton-on-Tees", "Suffolk", "Telford and Wrekin", "Warrington", "Warwickshire", "West Lothian",
    "West Sussex", "Wigan", "Wiltshire", "Wolverhampton", "Worcestershire"
  ].freeze

  class << self
    def country_name_for(location)
      parts = split_parts(location)
      return if parts.empty?

      override = location_override(location)
      return override.split(", ").last if override.present?

      if parts.size == 1
        city_country = city_country_for(parts.first)
        return city_country if city_country.present?
      end

      explicit = explicit_country_name_from_parts(parts)
      return explicit if explicit

      parts.reverse_each do |part|
        token = normalize_token(part)
        next unless us_state_code?(token)

        return "United States"
      end

      parts.reverse_each do |part|
        country = administrative_region_country(part)
        return country if country.present?
      end

      nil
    end

    def iso_code_for(location)
      parts = split_parts(location)
      return if parts.empty?

      override = location_override(location)
      if override.present?
        country = override.split(", ").last
        iso_code = iso_code_for_country_name(country)
        return iso_code if iso_code.present?
      end

      if parts.size == 1
        city_country = city_country_for(parts.first)
        iso_code = iso_code_for_country_name(city_country) if city_country.present?
        return iso_code if iso_code.present?
      end

      explicit_iso = explicit_country_iso_from_parts(parts)
      return explicit_iso if explicit_iso

      parts.reverse_each do |part|
        token = normalize_token(part)
        return "US" if us_state_code?(token)
      end

      parts.reverse_each do |part|
        country = administrative_region_country(part)
        iso_code = iso_code_for_country_name(country) if country.present?
        return iso_code if iso_code.present?
      end

      nil
    end

    def normalize_location_string(location)
      return if location.blank?

      parts = split_parts(location)
      return location if parts.size <= 1

      country_name = country_name_for(location)
      return if country_name.blank?
      return if parts.any? { |part| explicit_country_part?(part) }

      "#{parts.first}, #{country_name}"
    end

    def format_for_display(location)
      return if location.blank?

      override = location_override(location)
      return override if override.present?

      parts = split_parts(location)
      if parts.size == 1
        country = city_country_for(parts.first)
        return "#{parts.first}, #{country}" if country.present?

        return parts.first
      end

      normalized = normalize_location_string(location)
      return normalized if normalized.present?

      "#{parts.first}, #{parts.last}"
    end

    def normalize_country_name(country)
      normalized_country = country.to_s.squish
      without_crunchbase_prefix = normalized_country.sub(/\ANA\s*-\s*/i, "")
      without_trailing_digits = without_crunchbase_prefix.sub(/\d+\z/, "")

      COUNTRY_ALIASES[without_crunchbase_prefix] ||
        COUNTRY_ALIASES[without_trailing_digits] ||
        ADMINISTRATIVE_REGION_COUNTRIES[without_crunchbase_prefix] ||
        (UK_ADMINISTRATIVE_AREAS.include?(without_crunchbase_prefix) ? "United Kingdom" : nil) ||
        without_crunchbase_prefix
    end

    private

    def split_parts(location)
      location.to_s.split(",").map { |part| part.strip.gsub(/[^\p{L}\p{N}\s'-]/, "") }.reject(&:blank?)
    end

    def normalize_token(value)
      value.to_s.strip.downcase.gsub(/\Athe\s+/, "").gsub(/\./, "")
    end

    def us_state_code?(token)
      token.match?(/\A[a-z]{2}\z/) && US_STATE_CODES.include?(token.upcase)
    end

    def iso_code_for_country_name(country_name)
      COUNTRY_ISO_CODES[normalize_token(country_name)]
    end

    def canonical_country?(country_name)
      iso_code_for_country_name(country_name).present?
    end

    def explicit_country_part?(part)
      explicit_country_iso_from_parts([part]).present? || explicit_country_name_from_parts([part]).present?
    end

    def explicit_country_iso_from_parts(parts)
      parts.reverse_each do |part|
        token = normalize_token(part)
        return COUNTRY_ISO_CODES[token] if COUNTRY_ISO_CODES.key?(token)

        cleaned = cleaned_part(part)
        alias_name = COUNTRY_ALIASES[cleaned]
        if alias_name.present?
          iso_code = iso_code_for_country_name(alias_name)
          return iso_code if iso_code.present?
        end
      end

      nil
    end

    def explicit_country_name_from_parts(parts)
      parts.reverse_each do |part|
        cleaned = cleaned_part(part)
        alias_name = COUNTRY_ALIASES[cleaned]
        return alias_name if alias_name.present? && canonical_country?(alias_name)

        token = normalize_token(part)
        return cleaned if COUNTRY_ISO_CODES.key?(token)
      end

      nil
    end

    def administrative_region_country(part)
      cleaned = cleaned_part(part)
      ADMINISTRATIVE_REGION_COUNTRIES[cleaned] ||
        (UK_ADMINISTRATIVE_AREAS.include?(cleaned) ? "United Kingdom" : nil)
    end

    def cleaned_part(part)
      part.to_s.squish.sub(/\ANA\s*-\s*/i, "").sub(/\d+\z/, "")
    end

    def location_override(location)
      cleaned = location.to_s.squish
      LOCATION_OVERRIDES[cleaned] ||
        LOCATION_OVERRIDES.find { |key, _| normalize_token(key) == normalize_token(cleaned) }&.last
    end

    def city_country_for(city)
      cleaned = cleaned_part(city)
      return CITY_COUNTRIES[cleaned] if CITY_COUNTRIES.key?(cleaned)

      CITY_COUNTRIES.each do |city_name, country|
        return country if normalize_token(city_name) == normalize_token(cleaned)
      end

      nil
    end

    COUNTRY_ISO_CODES = CompaniesHelper::COUNTRY_ISO_CODES
  end
end
