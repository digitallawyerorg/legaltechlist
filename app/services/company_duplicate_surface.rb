# Everything the reviewer needs to decide a duplicate on the record in front of them:
# which other entries match, why each one matched, and what state each is in.
#
# The sidebar this replaces listed bare names on two keys. A reviewer could not tell a
# live public entry from an unpublished draft or from something already rejected — and
# those resolve in opposite directions. It also could not see a cross-domain duplicate
# at all: a rebrand on a new domain matches on neither the exact name nor the domain,
# which is the case the core-name key exists for.
#
# Nothing here changes a record. Resolving a duplicate stays a human decision, made
# with both records open.
class CompanyDuplicateSurface
  DOMAIN = "Same canonical domain".freeze
  NAME = "Same normalized name".freeze
  CORE_NAME = "Same name once corporate and product suffixes are stripped".freeze

  Match = Struct.new(:company, :reasons, keyword_init: true) do
    # A rejected entry is a decision that has already been made, so it is shown for
    # context but does not stand in the way of publishing this one.
    def unresolved? = company.quality_status != "rejected"
    def status_label = company.review_state_label
    def status_badge_class = company.review_state_badge_class
    def visibility_label = company.visible? ? "Public" : "Not public"
    def reason_text = reasons.to_sentence
  end

  def self.call(company) = new(company).call

  def initialize(company)
    @company = company
  end

  def call
    matches = Hash.new { |hash, key| hash[key] = [] }

    Company.duplicates_by_domain_for(company).each { |match| matches[match] << DOMAIN }
    Company.duplicates_by_normalized_name_for(company).each { |match| matches[match] << NAME }
    Company.duplicates_by_core_name_for(company).each do |match|
      # Saying the same thing twice is noise: the core-name key only tells a reviewer
      # something the exact-name key has not already told them.
      matches[match] << CORE_NAME unless matches[match].include?(NAME)
    end

    matches.map { |match, reasons| Match.new(company: match, reasons: reasons.uniq) }
           .sort_by { |match| [match.unresolved? ? 0 : 1, match.company.name.to_s] }
  end

  private

  attr_reader :company
end
