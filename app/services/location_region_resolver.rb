class LocationRegionResolver
  NORTH_AMERICA = "North America".freeze
  EUROPE = "Europe".freeze
  ASIA_PACIFIC = "Asia-Pacific".freeze
  LATIN_AMERICA = "Latin America".freeze
  MIDDLE_EAST = "Middle East".freeze
  AFRICA = "Africa".freeze
  OTHER = "Other".freeze

  REGION_ISO_CODES = {
    NORTH_AMERICA => %w[US CA].freeze,
    EUROPE => %w[
      GB IE
      AL AD AM AT BY BE BA BG HR CY CZ DK EE FI FR DE GE GR HU IS IT LV LI LT LU MT MD ME NL MK NO PL PT RO RS RU SK SI ES SE CH TR UA
      XK MC SM VA
    ].freeze,
    ASIA_PACIFIC => %w[
      AF AU BD BN KH CN HK IN ID JP KZ KG LA MY MN MM NP NZ PK PH SG KR LK TW TH TJ TM UZ VN
    ].freeze,
    LATIN_AMERICA => %w[AR BO BR CL CO CR CU DO EC SV GT HN JM KY MX NI PA PY PE PR TT UY VE].freeze,
    MIDDLE_EAST => %w[BH EG IQ IR IL JO KW LB OM PS QA SA SY AE YE].freeze,
    AFRICA => %w[
      DZ AO BW BI CM CV CF TD KM CD CI DJ GQ ER SZ ET GA GM GH GN GW KE LS LR LY MG MW ML MR MU MA MZ NA NE NG RW ST SN SC SL SO ZA SS SD TZ TG TN UG EH ZM ZW
    ].freeze
  }.freeze

  ISO_TO_REGION = REGION_ISO_CODES.each_with_object({}) do |(region, iso_codes), map|
    iso_codes.each { |iso| map[iso] = region }
  end.freeze

  def self.region_for_country(country_name)
    normalized = LocationCountryResolver.normalize_country_name(country_name)
    return OTHER if normalized.blank?

    iso = LocationCountryResolver.country_iso_code(normalized)
    return OTHER if iso.blank?

    ISO_TO_REGION[iso] || OTHER
  end

  def self.region_for_location(location)
    country = LocationCountryResolver.country_name_for(location)
    return OTHER unless country

    region_for_country(country)
  end
end
