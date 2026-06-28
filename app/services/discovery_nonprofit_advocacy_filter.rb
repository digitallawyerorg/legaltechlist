class DiscoveryNonprofitAdvocacyFilter
  STRONG_SIGNAL_PATTERN = /\b(nonprofit|non-profit|501\s*\(\s*c\s*\)|advocacy\s+(group|organization|org)|tenant\s+union|legal\s+aid\s+(organization|nonprofit|non-profit)|pro\s+bono\s+(nonprofit|organization|initiative)|community\s+legal\s+(clinic|services)|public\s+interest\s+(law|legal)|civil\s+rights\s+(nonprofit|organization)|grassroots\s+(legal|housing))\b/i
  VENDOR_SIGNAL_PATTERN = /\b(saas|software\s+(platform|vendor|company)|for\s+law\s+firms|enterprise|b2b|legal\s+tech(nology)?\s+(company|vendor|startup|platform))\b/i

  def self.rejected?(candidate)
    new(candidate).rejected?
  end

  def self.rejection_reason(candidate)
    new(candidate).rejection_reason
  end

  def initialize(candidate)
    @candidate = candidate
  end

  def rejected?
    rejection_reason.present?
  end

  def rejection_reason
    return @rejection_reason if defined?(@rejection_reason)

    @rejection_reason = compute_rejection_reason
  end

  private

  attr_reader :candidate

  def compute_rejection_reason
    return if vendor_signals?

    return "nonprofit_advocacy_keyword" if text.match?(STRONG_SIGNAL_PATTERN)
    return "nonprofit_org_domain" if org_domain? && text.match?(/\b(nonprofit|non-profit|advocacy|legal\s+aid|tenant|housing\s+justice|debt\s+relief|bankruptcy\s+assistance)\b/i)

    nil
  end

  def text
    [
      candidate["name"],
      candidate["website"],
      candidate["description"],
      candidate["why_discovered"],
      candidate["location"]
    ].compact.join(" ").downcase
  end

  def org_domain?
    domain = Company.canonical_domain_for(candidate["website"])
    domain.present? && domain.end_with?(".org")
  end

  def vendor_signals?
    text.match?(VENDOR_SIGNAL_PATTERN)
  end
end
