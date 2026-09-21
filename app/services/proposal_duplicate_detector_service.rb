# Resolves, live, whether a proposal describes a company the index already holds or
# another open proposal already covers.
#
# This replaces the intake-time snapshot that used to be written once into
# CompanyProposal#duplicate_signals and never recomputed. That snapshot meant the
# approval gate could be reading a months-old view of the index, and because it only
# ever compared a candidate against Company rows, two proposals for the same company
# stayed mutually invisible and could both be approved.
#
# The identity keys themselves — what makes two records the same company, and how each
# side is normalized — live in CompanyIdentityMatcher, which every other duplicate
# instrument now shares. This service is the proposal-shaped caller: it decides what the
# candidate's name, domains and profiles are, compares against the open queue as well as
# the index, and writes the reviewer-facing summary.
class ProposalDuplicateDetectorService
  BLOCKING_MATCH_TYPES = CompanyIdentityMatcher::MATCH_TYPES

  # How far the evidence actually goes. Both tiers still require a human to resolve
  # before approval — the Avokati AI pair that reached the public site matched on name
  # alone — but the reviewer is told which of the two they are looking at, and the
  # system never asserts "duplicate" on a name coincidence.
  #
  #   confirmed  same canonical domain, a domain that redirects to it, a shared LinkedIn
  #              or Crunchbase company page, or a matching name corroborated by one.
  #   possible   a name or brand match with nothing else agreeing, or a shared domain with
  #              materially different names (one company, likely two products).
  CONFIDENCE_CONFIRMED = CompanyIdentityMatcher::CONFIDENCE_CONFIRMED
  CONFIDENCE_POSSIBLE = CompanyIdentityMatcher::CONFIDENCE_POSSIBLE

  def self.call(**kwargs)
    new(**kwargs).call
  end

  # Kept as the entry point several callers already use for name normalization.
  def self.core_name(value) = CompanyIdentityMatcher.core_name(value)

  # extra_domains lets a caller feed in domains discovered by actually fetching the
  # candidate's site (see SiteEvidenceFetcherService), which is what makes the
  # redirect key work on the proposal side.
  def initialize(proposal:, extra_domains: [])
    @proposal = proposal
    @extra_domains = Array(extra_domains).compact_blank.map { |d| d.to_s.downcase }
  end

  def call
    company_hits = company_matches
    proposal_hits = proposal_matches

    {
      # A record that matches on both keys belongs in both lists. Bucketing on the single
      # strongest key hid the name agreement behind the domain agreement, which is the
      # corroboration a reviewer most needs to see.
      "name_matches" => CompanyIdentityMatcher.name_matches(company_hits),
      "domain_matches" => CompanyIdentityMatcher.domain_matches(company_hits),
      "proposal_matches" => proposal_hits,
      "recommended_action" => recommended_action(company_hits, proposal_hits),
      "blocking" => (company_hits + proposal_hits).any? { |hit| hit["match_type"].in?(BLOCKING_MATCH_TYPES) },
      "confidence" => overall_confidence(company_hits + proposal_hits),
      "checked_at" => Time.current.utc.iso8601
    }
  end

  private

  attr_reader :proposal, :extra_domains

  def changes
    @changes ||= proposal.editable_changes
  end

  def candidate_name
    @candidate_name ||= changes["name"].presence || proposal.source_payload["name"].presence
  end

  def normalized_name
    @normalized_name ||= Company.normalized_name_value(candidate_name)
  end

  def candidate_core
    return @candidate_core if defined?(@candidate_core)

    @candidate_core = CompanyIdentityMatcher.core_key(candidate_name)
  end

  # Domains the record itself claims, as distinct from domains discovered by following
  # its redirects. A match on a domain the record never declared is the signature of a
  # rebrand, and the reviewer needs to be told that rather than just "duplicate".
  def declared_domains
    @declared_domains ||= [changes["main_url"], proposal.source_payload["website"], changes["source_url"]]
                          .map { |url| Company.canonical_domain_for(url) }.compact_blank.uniq
  end

  def candidate_domains
    @candidate_domains ||= (declared_domains + extra_domains).uniq
  end

  def candidate_profiles
    @candidate_profiles ||= CompanyIdentityMatcher.profile_keys(
      "linkedin_url" => changes["linkedin_url"].presence || proposal.source_payload["linkedin_url"],
      "crunchbase_url" => changes["crunchbase_url"].presence || proposal.source_payload["crunchbase_url"]
    )
  end

  # ---- company side ------------------------------------------------------

  def matcher
    @matcher ||= CompanyIdentityMatcher.new(
      name: candidate_name,
      domains: candidate_domains,
      declared_domains: declared_domains,
      profiles: candidate_profiles,
      # A proposal that has already minted its own company is not a duplicate of it:
      # without this, promoting an approved draft re-checks duplicates, finds the row the
      # proposal itself created, and blocks its own publication. A REJECTED proposal is
      # the other case — its company link records the entry that was kept instead, so
      # that relationship must stay visible.
      exclude_company_id: (proposal.company_id if proposal.company_id.present? && !proposal.rejected?)
    )
  end

  def company_matches
    @company_matches ||= matcher.matches
  end

  def overall_confidence(hits)
    return nil if hits.empty?

    hits.any? { |hit| hit["confidence"] == CONFIDENCE_CONFIRMED } ? CONFIDENCE_CONFIRMED : CONFIDENCE_POSSIBLE
  end

  # ---- sibling-proposal side ---------------------------------------------

  def proposal_matches
    return [] if normalized_name.blank? && candidate_domains.empty?

    sibling_proposals.filter_map do |sibling|
      sibling_changes = sibling.editable_changes
      sibling_name = sibling_changes["name"].presence || sibling.source_payload["name"].presence
      sibling_domains = [sibling_changes["main_url"], sibling.source_payload["website"]]
                        .map { |url| Company.canonical_domain_for(url) }.compact_blank.uniq

      match_type = sibling_match_type(sibling_name, sibling_domains)
      next unless match_type

      {
        "proposal_id" => sibling.id,
        "name" => sibling.display_name,
        "main_url" => sibling_changes["main_url"],
        "status" => sibling.status,
        "created_at" => sibling.created_at&.utc&.iso8601,
        "match_type" => match_type,
        # The older record is the one an operator has probably already looked at, so
        # name a default canonical rather than leaving the choice unframed.
        "is_older" => sibling.created_at.present? && proposal.created_at.present? && sibling.created_at < proposal.created_at
      }
    end.first(CompanyIdentityMatcher::MAX_MATCHES)
  end

  def sibling_match_type(sibling_name, sibling_domains)
    return "exact_domain" if (candidate_domains & sibling_domains).any?
    return "related_domain" if candidate_domains.product(sibling_domains).any? { |mine, theirs| CompanyIdentityMatcher.related_domains?(mine, theirs) }

    sibling_normalized = Company.normalized_name_value(sibling_name)
    return "exact_name" if normalized_name.present? && sibling_normalized == normalized_name

    sibling_core = CompanyIdentityMatcher.core_key(sibling_name)
    return "core_name" if candidate_core.present? && sibling_core == candidate_core

    sibling_brands = ([sibling_core] + sibling_domains.map { |domain| CompanyIdentityMatcher.brand_key(domain) }).compact_blank
    candidate_brands = ([candidate_core] + candidate_domains.map { |domain| CompanyIdentityMatcher.brand_key(domain) }).compact_blank
    return "brand_name" if (candidate_brands & sibling_brands).any?

    nil
  end

  def sibling_proposals
    scope = CompanyProposal.pending_review
    scope = scope.where.not(id: proposal.id) if proposal.id.present?
    scope
  end

  # ---- reviewer-facing summary -------------------------------------------

  def recommended_action(company_hits, proposal_hits)
    # Never narrate a duplicate against empty arrays. The stored signals used to carry
    # "Review duplicate domain before approval." whenever the submission had a URL at
    # all, which reviewers learned to read as noise — in both directions.
    return nil if company_hits.empty? && proposal_hits.empty?

    parts = []
    if (company_hit = company_hits.first)
      label = "#{company_hit['name']} (##{company_hit['id']})"
      parts << if matcher.rebrand?(company_hit)
        "#{label} already covers #{company_hit['matched_value']} — this looks like a rebrand, so update that entry rather than creating a new one. Compare the two records to see what this proposal adds."
      elsif company_hit["match_type"] == "prior_name"
        "#{label} was previously listed as #{company_hit['matched_value']} — this looks like the same company under a later name. Compare the two records rather than creating a second entry."
      elsif company_hit["match_type"] == "brand_name"
        "#{label} already publishes the brand #{company_hit['matched_value']} on a different address. Compare the two records: this is either the same product listed twice or two products sharing a name, and only one of those is a duplicate."
      elsif company_hit["match_type"] == "shared_profile"
        "#{label} points at the same #{company_hit['matched_value'].to_s.split(':').first} page, so it is the same company under a different name or website. Compare the two records rather than creating a second entry."
      elsif company_hit["confidence"] == CONFIDENCE_POSSIBLE && company_hit["match_type"].in?(%w[exact_domain related_domain])
        "#{label} shares this website but has a different name — it may be a different product from the same company. Compare the two records before treating this as a duplicate."
      elsif company_hit["confidence"] == CONFIDENCE_POSSIBLE
        "Possibly the same company as #{label}, matched on name alone with nothing else agreeing. Compare the two records to confirm before resolving."
      else
        corroboration = Array(company_hit["shared_profiles"]).presence
        basis = corroboration ? "name and a shared #{corroboration.to_sentence} profile" : "website"
        "#{label} is already in the index (matched on #{basis}). Compare the two records to see whether this proposal has anything the existing entry lacks, then keep one."
      end
    end

    if (proposal_hit = proposal_hits.first)
      canonical = proposal_hit["is_older"] ? "Proposal ##{proposal_hit['proposal_id']} is the earlier record" : "This is the earlier record"
      parts << "Proposal ##{proposal_hit['proposal_id']} covers the same company. #{canonical}; keep one and reject the other."
    end

    parts.join(" ")
  end
end
