class LocationRegionResolver
  UNITED_STATES = "United States".freeze
  CANADA = "Canada".freeze
  UK_IRELAND = "United Kingdom & Ireland".freeze
  EUROPE = "Europe".freeze
  ASIA_PACIFIC = "Asia-Pacific".freeze
  LATIN_AMERICA = "Latin America".freeze
  MIDDLE_EAST_AFRICA = "Middle East & Africa".freeze
  OTHER = "Other".freeze

  REGION_ISO_CODES = {
    UNITED_STATES => %w[US].freeze,
    CANADA => %w[CA].freeze,
    UK_IRELAND => %w[GB IE].freeze,
    EUROPE => %w[
      AL AD AM AT BY BE BA BG HR CY CZ DK EE FI FR DE GE GR HU IS IT LV LI LT LU MT MD ME NL MK NO PL PT RO RS RU SK SI ES SE CH TR UA
      XK MC SM VA
    ].freeze,
    ASIA_PACIFIC => %w[
      AF AU BD BN KH CN HK IN ID JP KZ KG LA MY MN MM NP NZ PK PH SG KR LK TW TH TJ TM UZ VN
    ].freeze,
    LATIN_AMERICA => %w[AR BO BR CL CO CR CU DO EC SV GT HN JM MX NI PA PY PE PR TT UY VE].freeze,
    MIDDLE_EAST_AFRICA => %w[
      DZ AO BH BW BI CM CV CF TD KM CD DJ EG GQ ER SZ ET GA GM GH GN GW IQ IR IL JO KE KW LB LS LR LY MG MW ML MR MU MA MZ NA NE NG OM PS QA RW ST SA SN SC SL SO ZA SS SD SY TZ TG TN UG AE EH YE ZM ZW
    ].freeze
  }.freeze

  ISO_TO_REGION = REGION_ISO_CODES.each_with_object({}) do |(region, iso_codes), map|
    iso_codes.each { |iso| map[iso] = region }
  end.freeze

  def self.region_for_country(country_name)
    normalized = LocationCountryResolver.normalize_country_name(country_name)
    return OTHER if normalized.blank?

    iso = LocationCountryResolver.iso_code_for("_, #{normalized}")
    return OTHER if iso.blank?

    ISO_TO_REGION[iso] || OTHER
  end

  def self.region_for_location(location)
    country = LocationCountryResolver.country_name_for(location)
    return OTHER unless country

    region_for_country(country)
  end
end
