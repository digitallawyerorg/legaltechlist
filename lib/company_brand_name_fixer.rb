# frozen_string_literal: true

module CompanyBrandNameFixer
  LEGAL_SUFFIX = /\s*(?:\([^)]*\))?\s*(?:(?:PRIVATE|PVT\.?)\s+)?(?:LIMITED|LTD\.?|L\.?L\.?P\.?|L\.?L\.?C\.?|OÜ|OU|GMBH|INCORPORATED|INC\.?|CORP(?:ORATION)?\.?|CO\.?\s+LTD\.?|PLC|PTY\.?\s+LTD\.?|S\.?A\.?S\.?|B\.?V\.?|AG|PROFESSIONAL\s+CORP\.?)\.?$/i

  SUFFIX_PATTERN = /\b(LIMITED|LTD\.?|LLP|LLC|OÜ|OU|GMBH|INC\.?|CORP\.?|CORPORATION|PRIVATE LIMITED|PVT\.? LTD\.?|CO\.? LTD\.?|S\.?A\.?S\.?|B\.?V\.?|AG|PLC|PTY\.? LTD\.?|PROFESSIONAL CORP\.?)\b/i

  CONSULTANCY_PATTERNS = [
    /\bis a (?:[\w\s&'.-]+ )?consultancy\b/i,
    /\bconsulting firm\b/i,
    /\b(?:managed IT|legal technology|legal-data risk|management) consultancy\b/i,
    /\b(?:digital marketing|marketing) agency\b/i,
    /\bis a [\w\s&'.-]+ law firm\b/i,
    /\b(?:immigration|business|financial-regulatory|Lagos-based|London-based) law firm\b/i,
    /\bnotarial practice\b/i,
    /\bnotary public limited\b/i,
    /\bexpert-witness\b/i,
    /\bfractional (?:privacy|compliance)\b/i,
    /\boutsourced legal (?:cashiering|bookkeeping)\b/i,
    /\bmanaged IT consultancy\b/i,
    /\blegal technology consulting\b/i,
    /\bforensic expert-witness\b/i,
    /\bwas a [\w\s]+ legal practice\b/i,
    /\boffers (?:forensic|fractional)\b/i,
    /\bdelivers AI education\b/i,
    /\bfractional compliance leadership\b/i,
    /\bentity formation, regulatory licensing\b/i,
    /\bcompany formation, regulatory\b/i
  ].freeze

  PRODUCT_SIGNAL = /\b(?:develops|operates|builds|provides)\b.{0,80}\b(?:software|platform|SaaS|application|tool|app|AI[- ]enabled|cloud-based|web-based)\b/i

  RENAME_OVERRIDES = {
    15_093 => "LegallyLite",
    15_052 => "eSignature",
    15_056 => "BY Sirius Group",
    15_078 => "Justifi",
    15_050 => "FullHouseAI",
    15_048 => "Exodia Technologies",
    15_064 => "MoveSorted",
    15_071 => "PlanOps",
    15_074 => "Leaseholdr"
  }.freeze

  HIDE_IDS = [].freeze

  module_function

  def legal_entity_caps?(company)
    name = company.name.to_s
    return false if name.blank?

    letters = name.gsub(/[^A-Za-z]/, "")
    return false if letters.blank?

    upper_ratio = letters.chars.count { |ch| ch == ch.upcase && ch != ch.downcase }.to_f / letters.length
    (upper_ratio >= 0.7 || name == name.upcase) && name.match?(SUFFIX_PATTERN)
  end

  def mixed_case_legal_suffix?(company)
    name = company.name.to_s
    name.match?(SUFFIX_PATTERN) && !legal_entity_caps?(company)
  end

  def consultancy?(company)
    return true if HIDE_IDS.include?(company.id)

    desc = company.description.to_s.strip
    return false if desc.blank?

    lead = desc[0, 280]
    return false unless CONSULTANCY_PATTERNS.any? { |pattern| lead.match?(pattern) }
    return false if lead.match?(PRODUCT_SIGNAL) && lead.match?(/\bdevelops\b/i)

    true
  end

  def proposed_name(company)
    return RENAME_OVERRIDES[company.id] if RENAME_OVERRIDES.key?(company.id)

    from_description = brand_from_description(company.description, company.name)
    return from_description if from_description.present?

    stripped = strip_legal_suffix(company.name)
    return stripped if stripped.match?(/[a-z]/) && stripped != company.name

    smart_title_case(stripped)
  end

  def brand_from_description(description, legal_name)
    desc = description.to_s.strip
    return nil if desc.blank?

    if (match = desc.match(/\A([A-Za-z0-9&][^.]{0,80}?)\s+operates\s+([A-Za-z0-9][\w.-]{1,50}?)(?:,|\s+a\s)/i))
      brand, product = match[1].strip, match[2].strip
      return product.sub(/\.(com|io|ai|llc|app)$/i, "") if product.match?(/[a-z]/) && !names_similar?(product, legal_name)
      return brand unless names_similar?(brand, legal_name)
    end

    if (match = desc.match(/\A([A-Za-z0-9&][^.]{0,80}?)\s+(?:develops|is|offers|provides|builds)\b/i))
      candidate = match[1].strip
      return candidate unless names_similar?(candidate, legal_name)
    end

    nil
  end

  def strip_legal_suffix(name)
    name.to_s.gsub(LEGAL_SUFFIX, "").squish
  end

  def names_similar?(candidate, legal_name)
    na = Company.normalized_name_value(candidate)
    nb = Company.normalized_name_value(legal_name)
    return true if na == nb
    return false if nb == na || nb.start_with?("#{na} ")

    na.include?(nb) || nb.include?(na)
  end

  def smart_title_case(value)
    words = value.to_s.split(/\s+/)
    words.map.with_index do |word, index|
      if word.match?(/\A[A-Z]{2,}\z/) && word != "AI" && word.length > 3
        word.capitalize
      elsif word.match?(/[a-z]/)
        word
      elsif word.match?(/AI$/i)
        word.sub(/AI$/i, "AI")
      elsif index.zero? && word.upcase == "BY"
        "BY"
      else
        word.capitalize
      end
    end.join(" ")
  end

  def review_company(company)
    if consultancy?(company)
      return { action: :hide, reason: "consultancy or out-of-scope service provider" }
    end

  if legal_entity_caps?(company) || mixed_case_legal_suffix?(company)
      new_name = proposed_name(company)
      if new_name.present? && new_name != company.name
        return { action: :rename, new_name: new_name, reason: "legal entity name to product/brand name" }
      end
    end

    { action: :skip }
  end

  def apply!(company, result, dry_run: true)
    case result[:action]
    when :hide
      if dry_run
        result
      else
        company.update!(
          visible: false,
          status: "inactive",
          verification_verdict: "out_of_scope_review"
        )
        result.merge(applied: true)
      end
    when :rename
      if dry_run
        result
      else
        attrs = { name: result[:new_name] }
        if company.respond_to?(:canonical_domain) && company.main_url.present?
          attrs[:fingerprint] = company.calculated_fingerprint
          attrs[:canonical_domain] = company.canonical_main_domain
        end
        company.update!(attrs)
        result.merge(applied: true)
      end
    else
      result
    end
  end
end
