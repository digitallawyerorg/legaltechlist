# The one place that answers "does the index already hold this company?".
#
# Four instruments used to answer that question four different ways. The intake triage
# compared canonical domains against *visible* rows only, duplicate_check and the agent
# lookup tool compared exact normalized names, and only the approval gate looked at
# anything more. So a submission for a company the index already publishes cleared every
# check ahead of the gate whenever the brand had moved on: a new name, a new domain, a new
# TLD, or a row approved into a hidden draft. That is how a published entry and a fresh
# submission for the same product sat in the queue side by side with nothing flagged.
#
# Identity keys, strongest first:
#
#   exact_domain    the same canonical domain.
#   redirect_domain the candidate's site resolves to a domain the index already holds.
#   related_domain  one domain sits under the other (app.foo.com / foo.com). Skipped on
#                   shared hosts, where two subdomains are two companies.
#   shared_profile  the same LinkedIn or Crunchbase company page. The only key that
#                   survives both a rename and a domain move.
#   exact_name      the same normalized name.
#   prior_name      the candidate's name is one the entry used to carry, recovered from
#                   its slug (assigned once, so it outlives a rename) and from the name
#                   changes recorded in its field-edit history.
#   core_name       the same name once corporate form and trailing product words go.
#   brand_name      the same brand string, wherever each record carries it: in its name,
#                   or in its domain's registrable label. A product published under its
#                   parent's company name is only nameable from the domain, and a brand
#                   reappearing on another TLD matches no domain at all — deep-law.com
#                   against an entry publishing Deep Law at deep-law.io matched nothing
#                   before this key, on either side, by any spelling.
#
# Every key is blocking: each means a human has to compare two records. None asserts a
# duplicate on its own, and brand_name deliberately resolves as no better than possible —
# three unrelated products have shipped as "Deep Law". Comparison is the point.
class CompanyIdentityMatcher
  CACHE_TTL = 5.minutes
  # Bumped whenever an index row gains a key. A row cached in the previous shape is
  # missing the new one, which silently turns the new match type off until it expires.
  CACHE_SHAPE = "v2".freeze

  DOMAIN_MATCH_TYPES = %w[exact_domain redirect_domain related_domain].freeze
  # shared_profile, prior_name and brand_name are grouped with the name keys because they
  # identify a company rather than a website. The two buckets are how every reader already
  # splits these, and a third would have to be threaded through the views and the tools.
  NAME_MATCH_TYPES = %w[shared_profile exact_name prior_name core_name brand_name].freeze
  # Order is precedence: the strongest true statement about why two records matched.
  MATCH_TYPES = (DOMAIN_MATCH_TYPES + NAME_MATCH_TYPES).freeze

  CONFIDENCE_CONFIRMED = "confirmed".freeze
  CONFIDENCE_POSSIBLE = "possible".freeze

  MAX_MATCHES = 10

  # Corporate form, and the filler around it. These carry no identity wherever they
  # appear, so they are dropped from anywhere in the name.
  CORPORATE_FORMS = %w[
    inc incorporated llc pllc llp lp ltd limited ltda lda plc corp corporation co company
    gmbh mbh ug ag sa sas sasu sarl srl srls eurl sl slu sau spa nv bv ab asa as oy oyj
    aps ou kk kft zrt sro doo bhd sdn ehf ulc gbr kg kgaa pte pty pvt spzoo
    group holdings holding the and
  ].freeze

  # Descriptive product words. Dropped only from the END of a name, where they are a
  # suffix on a brand ("ClauseDelta platform").
  #
  # Dropping them anywhere is what made "Cloud Contracts 365" collide with "Contracts 365"
  # on core_name alone — two companies in two countries, one of them then rejected as a
  # duplicate of the other. A leading descriptive word is part of the brand, not a suffix
  # on it, so it stays.
  TRAILING_PRODUCT_WORDS = %w[
    labs lab software solutions systems technologies technology tech
    platform platforms global international services digital online cloud
    ai io app hq
  ].freeze

  # Legal forms written with periods or slashes — S.R.L., s.r.o., B.V., Sp. z o.o., A/S.
  # Normalization turns every punctuation run into a space, so by the time the token
  # filter sees them they are single letters that no single-token list can catch. Stripped
  # only from the end of the name, where a legal form sits.
  LEGAL_FORM_PHRASES = [
    %w[s r l], %w[s r o], %w[s a s], %w[s a], %w[s l], %w[s p a], %w[b v], %w[n v],
    %w[a g], %w[a s], %w[o u], %w[k k], %w[o y], %w[d o o], %w[p l c], %w[l l c],
    %w[l l p], %w[sp z o o], %w[s de r l], %w[co ltd], %w[pvt ltd], %w[pte ltd],
    %w[sdn bhd]
  ].freeze

  # Suffixes fused onto the end of a single token ("contractpodai"). Only stripped when
  # enough of the token survives to still identify a company, which keeps place names
  # such as Dubai and Mumbai intact.
  GLUED_SUFFIXES = %w[ai io app hq].freeze
  MIN_TOKEN_REMAINDER = 5

  # A core reducing to these describes a market, not a company, so it cannot carry a
  # duplicate claim on its own. The product words are here too: a name made of nothing
  # but them ("Online platform that") identifies no one.
  GENERIC_CORES = (%w[
    legal law lex juris justice legaltech lawtech contract contracts case cases
    document documents docs compliance counsel court courts advocate advocates
    attorney attorneys firm firms client clients matter matters practice ip
    that this these those which with from your their more best first next
    company companies startup startups service tool tools system data
    example test demo sample staging localhost website site home index www
  ] + TRAILING_PRODUCT_WORDS).freeze
  MIN_CORE_LENGTH = 4

  # Subdomains that are a different door into the same site. The subdomain key fires only
  # on these: any other label is a tenant name, and a host that hands out tenant
  # subdomains gives two unrelated companies two addresses under one domain, which would
  # make this key a false-positive engine rather than a rename detector.
  ENTRANCE_LABELS = %w[
    www www2 www3 web app apps my go get site portal platform account accounts
    secure login dashboard home info en us uk global public live www1
  ].freeze

  # Hosts that hand out subdomains to unrelated tenants. On these, two subdomains are two
  # companies, so the subdomain key must not fire even behind an entrance label.
  SHARED_HOSTS = %w[
    github.io gitlab.io wordpress.com blogspot.com wixsite.com editorx.io webflow.io
    squarespace.com myshopify.com substack.com medium.com notion.site super.site
    herokuapp.com netlify.app vercel.app pages.dev workers.dev firebaseapp.com web.app
    azurewebsites.net cloudfront.net appspot.com repl.co replit.app glitch.me
    weebly.com godaddysites.com carrd.co framer.website framer.app softr.app
    bubbleapps.io glideapp.io webnode.com jimdosite.com strikingly.com
    sharepoint.com zendesk.com freshdesk.com hubspotpagebuilder.com
    translate.goog s3.amazonaws.com
  ].freeze

  # Two-label registry suffixes. A host directly under one of these is a registrable
  # domain, not a subdomain of the suffix, and its brand label is the label before it.
  REGISTRY_SUFFIXES = %w[
    co.uk org.uk ac.uk gov.uk me.uk net.uk plc.uk ltd.uk
    com.au net.au org.au id.au com.br com.mx com.ar com.co com.pe
    co.in net.in org.in co.nz com.sg com.my com.hk com.tw com.cn
    co.jp or.jp ne.jp co.kr or.kr co.za org.za com.tr com.ua
    co.il com.il com.ph com.vn com.sa com.eg com.ng co.ke
  ].freeze

  # A LinkedIn company page or a Crunchbase organization page names one legal entity, so
  # two records pointing at the same page are the same company. A personal profile
  # (/in/...) is not, and neither is a bare or generic path — intake validates nothing, and
  # records have arrived with a company name sitting in linkedin_url, so matching on
  # whatever the last path segment happens to be would tie unrelated records together.
  PROFILE_PATH_ROOTS = {
    "linkedin" => %w[company showcase organization],
    "crunchbase" => %w[organization]
  }.freeze
  GENERIC_PROFILE_KEYS = %w[company companies organization organizations profile home index login example test].freeze
  MIN_PROFILE_KEY_LENGTH = 3

  PROFILE_KINDS = PROFILE_PATH_ROOTS.keys.freeze

  # Prior names recovered from each row's own field-edit history. Extracted in SQL so the
  # index stays small: the quality_review blob is large and only the "from" side of a name
  # change is wanted.
  PRIOR_NAMES_SQL = <<~SQL.squish.freeze
    CASE WHEN jsonb_typeof(companies.quality_review -> 'field_edits') = 'array' THEN (
      SELECT jsonb_agg(edit -> 'changes' -> 'name' ->> 'from')
      FROM jsonb_array_elements(companies.quality_review -> 'field_edits') AS edit
      WHERE edit -> 'changes' -> 'name' ->> 'from' IS NOT NULL
    ) END
  SQL

  # ---- normalization ------------------------------------------------------

  # The identity core of a name: corporate form dropped from anywhere, product words
  # dropped from the end, glued suffixes unfused. nil when what survives cannot assert
  # identity on its own.
  def self.core_name(value)
    tokens = Company.normalized_name_value(value).split
    tokens = tokens.map { |token| strip_glued_suffix(token) }
    tokens = drop_trailing_legal_forms(tokens)
    tokens = drop_trailing_product_words(tokens)
    core = tokens.reject { |token| token.in?(CORPORATE_FORMS) }.join(" ")
    return nil if core.blank?
    return nil if core.delete(" ").length < MIN_CORE_LENGTH
    return nil if core.split.all? { |token| token.in?(GENERIC_CORES) }

    core
  end

  # Spacing and punctuation are not identity: "Deep-Law", "Deep Law" and "deeplaw" are one
  # brand, and a search for any one of them used to return only the record spelled that
  # way. Comparing cores with the spaces out catches that without loosening what counts as
  # a core in the first place.
  def self.core_key(value)
    core_name(value)&.delete(" ")
  end

  def self.drop_trailing_legal_forms(tokens)
    tokens = tokens.dup
    loop do
      phrase = LEGAL_FORM_PHRASES.find { |candidate| candidate.length < tokens.length && tokens.last(candidate.length) == candidate }
      break unless phrase

      tokens = tokens.first(tokens.length - phrase.length)
    end
    tokens
  end

  def self.drop_trailing_product_words(tokens)
    tokens = tokens.dup
    tokens.pop while tokens.size > 1 && tokens.last.in?(TRAILING_PRODUCT_WORDS)
    tokens
  end

  def self.strip_glued_suffix(token)
    GLUED_SUFFIXES.each do |suffix|
      next unless token.end_with?(suffix)

      remainder = token[0..-(suffix.length + 1)]
      return remainder if remainder.length >= MIN_TOKEN_REMAINDER
    end
    token
  end

  # The brand label of a domain: the registrable label with the public suffix and any
  # subdomains removed, read as a name. deep-law.io and www.deep-law.com both give
  # "deeplaw"; app.foo.com gives "foo"; legal.io gives nil, being generic.
  def self.brand_key(domain)
    host = domain.to_s.downcase.delete_suffix(".")
    return nil if host.blank?

    labels = host.split(".")
    suffix_labels = REGISTRY_SUFFIXES.any? { |suffix| host.end_with?(".#{suffix}") } ? 2 : 1
    registrable = labels.last(suffix_labels + 1).join(".")
    # On a host that hands out tenant subdomains the registrable label is the platform's,
    # not the tenant's, so reading it as a brand would give every tenant the same one.
    return nil if registrable.in?(SHARED_HOSTS)

    core_key(labels[-(suffix_labels + 1)])
  end

  def self.profile_key(kind, url)
    segments = URI.parse(url.to_s.strip).path.to_s.downcase.split("/").reject(&:blank?)
    return nil unless segments.first.in?(PROFILE_PATH_ROOTS.fetch(kind, []))

    key = segments[1].to_s
    return nil if key.length < MIN_PROFILE_KEY_LENGTH || key.in?(GENERIC_PROFILE_KEYS)

    "#{kind}:#{key}"
  rescue URI::Error
    nil
  end

  def self.profile_keys(source)
    PROFILE_KINDS.each_with_object({}) do |kind, keys|
      key = profile_key(kind, source["#{kind}_url"])
      keys[kind] = key if key.present?
    end
  end

  # True when one host sits under the other by an entrance label — the same company
  # reached a different way. Refused on shared hosts, on a bare suffix, and on any label
  # that could be a tenant name.
  def self.related_domains?(one, other)
    return false if one.blank? || other.blank? || one == other

    child, parent = one.length > other.length ? [one, other] : [other, one]
    return false unless child.end_with?(".#{parent}")
    return false unless parent.count(".").positive?
    return false if parent.in?(SHARED_HOSTS) || parent.in?(REGISTRY_SUFFIXES)

    child.delete_suffix(".#{parent}").split(".").all? { |label| label.in?(ENTRANCE_LABELS) }
  end

  # Names an entry used to carry. The slug is assigned once, when the row is created, and
  # never follows a rename, so it is the cheapest record of what a company was called
  # before: the entry renamed from eSignLive to OneSpan still answers to esignlive.
  # Rebrands reach us under the old name often enough to be worth the lookup.
  def self.historical_name_values(slug:, prior_names: [], current_normalized: nil)
    candidates = Array(prior_names).compact_blank
    candidates += [slug.to_s.sub(/-\d+\z/, "").tr("-", " ")] if slug.present?

    candidates.flat_map { |value| [Company.normalized_name_value(value), core_key(value)] }
              .compact_blank
              .reject { |value| value == current_normalized }
              .select { |value| value.delete(" ").length >= MIN_CORE_LENGTH }
              .uniq
  end

  # ---- matching -----------------------------------------------------------

  # Every entry in the index that identifies the same company as the candidate.
  #
  # domains are every domain the candidate can be reached at, including any resolved by
  # fetching its site; declared_domains are the subset the record itself claims, which is
  # what lets a rebrand be described as one rather than reported as a bare duplicate.
  # The two buckets every reader splits matches into. A match can sit in both.
  def self.name_matches(matches)
    matches.select { |match| (Array(match["match_types"]) & NAME_MATCH_TYPES).any? }
  end

  def self.domain_matches(matches)
    matches.select { |match| (Array(match["match_types"]) & DOMAIN_MATCH_TYPES).any? }
  end

  def self.matches_for(name:, domains: [], declared_domains: nil, profiles: {}, exclude_company_id: nil)
    new(name: name, domains: domains, declared_domains: declared_domains, profiles: profiles, exclude_company_id: exclude_company_id).matches
  end

  def initialize(name:, domains: [], declared_domains: nil, profiles: {}, exclude_company_id: nil)
    @name = name
    @domains = normalize_domains(domains)
    @declared_domains = normalize_domains(declared_domains.nil? ? domains : declared_domains)
    @profiles = profiles.to_h.compact_blank
    @exclude_company_id = exclude_company_id
  end

  def matches
    return [] if normalized_name.blank? && domains.empty? && profiles.empty?

    self.class.index.filter_map do |row|
      next if exclude_company_id.present? && row[:id] == exclude_company_id

      match_types = match_types_for(row)
      next if match_types.empty?

      match_type = match_types.first
      {
        "id" => row[:id],
        "name" => row[:name],
        "main_url" => row[:main_url],
        "canonical_domain" => row[:domains].first,
        "visible" => row[:visible],
        "quality_status" => row[:quality_status],
        "match_type" => match_type,
        # Every key that agreed, strongest first. Two records usually match on more than
        # one, and a reader that sees only the strongest cannot tell a name coincidence
        # from a name match that the domain and the LinkedIn page both confirm.
        "match_types" => match_types,
        "matched_value" => matched_value_for(match_type, row),
        "confidence" => confidence_for(match_type, row),
        "shared_profiles" => shared_profiles(row)
      }
    end.sort_by { |hit| MATCH_TYPES.index(hit["match_type"]) }.first(MAX_MATCHES)
  end

  # True when the matched domain is one we only learned by resolving the candidate's site,
  # or one it never declared — the signature of a rebrand rather than a resubmission.
  def rebrand?(hit)
    return true if hit["match_type"] == "redirect_domain"

    hit["match_type"].in?(%w[exact_domain related_domain]) &&
      hit["matched_value"].present? && !declared_domains.include?(hit["matched_value"])
  end

  attr_reader :declared_domains

  private

  attr_reader :name, :domains, :profiles, :exclude_company_id

  def normalize_domains(values)
    Array(values).compact_blank.map { |domain| domain.to_s.downcase }.uniq
  end

  def normalized_name
    @normalized_name ||= Company.normalized_name_value(name)
  end

  def core_key
    return @core_key if defined?(@core_key)

    @core_key = self.class.core_key(name)
  end

  # Every brand string this candidate carries: its name, and the label of each of its
  # domains. Matching the set against the other record's set is what lets a name meet a
  # domain — a product named only in its parent's URL, or the same brand on another TLD.
  def brand_keys
    @brand_keys ||= ([core_key] + domains.map { |domain| self.class.brand_key(domain) }).compact_blank.uniq
  end

  def match_types_for(row)
    types = []
    types << "exact_domain" if (domains & row[:domains]).any?
    types << "redirect_domain" if row[:final_domain].present? && domains.include?(row[:final_domain])
    types << "related_domain" if related_domain_for(row).present?
    types << "shared_profile" if shared_profiles(row).any?
    types << "exact_name" if normalized_name.present? && row[:normalized] == normalized_name
    types << "prior_name" if prior_name_for(row).present?
    types << "core_name" if core_key.present? && row[:core] == core_key
    types << "brand_name" if brand_match_for(row).present?
    types
  end

  def related_domain_for(row)
    cached(:related, row) do
      (row[:domains] + [row[:final_domain]]).compact_blank.find do |theirs|
        domains.any? { |mine| self.class.related_domains?(mine, theirs) }
      end
    end
  end

  def prior_name_for(row)
    cached(:prior, row) { ([normalized_name.presence, core_key].compact_blank & row[:historical_names]).first }
  end

  def brand_match_for(row)
    cached(:brand, row) { (brand_keys & row[:brand_keys]).first }
  end

  def shared_profiles(row)
    cached(:profiles, row) { PROFILE_KINDS.select { |kind| profiles[kind].present? && profiles[kind] == row[:profiles][kind] } }
  end

  # One index row is asked about several keys per candidate, and the answer for a key is
  # the same every time it is asked.
  def cached(key, row)
    store = (@match_cache ||= {})[key] ||= {}
    store.fetch(row[:id]) { store[row[:id]] = yield }
  end

  def matched_value_for(match_type, row)
    case match_type
    when "exact_domain" then (domains & row[:domains]).first
    when "redirect_domain" then row[:final_domain]
    when "related_domain" then related_domain_for(row)
    when "shared_profile" then shared_profiles(row).first
    when "exact_name" then normalized_name
    when "prior_name" then prior_name_for(row)
    when "core_name" then core_key
    when "brand_name" then brand_match_for(row)
    end
  end

  def confidence_for(match_type, row)
    case match_type
    when "redirect_domain", "shared_profile"
      CONFIDENCE_CONFIRMED
    when "exact_domain", "related_domain"
      # One domain, and one domain tree, can host more than one product. Treat it as
      # confirmed only when the names agree too; otherwise say it may be a sibling.
      names_agree?(row) ? CONFIDENCE_CONFIRMED : CONFIDENCE_POSSIBLE
    else
      shared_profiles(row).any? ? CONFIDENCE_CONFIRMED : CONFIDENCE_POSSIBLE
    end
  end

  def names_agree?(row)
    return true if normalized_name.present? && row[:normalized] == normalized_name

    core_key.present? && row[:core] == core_key
  end

  # One pluck over the non-rejected index, with the derived match keys precomputed.
  #
  # Hidden drafts are included on purpose: approving a proposal that duplicates an
  # unpublished draft still mints a second row, and a hidden row is exactly the state a
  # published-but-404 entry is in. Every hidden mint that the guard cannot see degrades
  # the instrument used to clear the next submission.
  def self.index
    Rails.cache.fetch("company_identity_matcher/#{CACHE_SHAPE}/#{Company.duplicate_candidate_cache_version}", expires_in: CACHE_TTL) do
      Company.where("companies.quality_status IS DISTINCT FROM ?", "rejected")
             .pluck(
               :id, :name, :slug, :canonical_domain, :main_url, :visible, :quality_status,
               Arel.sql("companies.url_health->>'final_url'"), :linkedin_url, :crunchbase_url,
               Arel.sql(PRIOR_NAMES_SQL)
             )
             .map { |row| index_row(*row) }
    end
  end

  def self.index_row(id, name, slug, canonical_domain, main_url, visible, quality_status, final_url, linkedin_url, crunchbase_url, prior_names)
    normalized = Company.normalized_name_value(name)
    # canonical_domain is a stored derivation and is NOT recomputed when main_url is
    # changed by the auto-apply path, so a record can be invisible to a check on its own
    # current website while still matching a domain it no longer uses. Carry both, and let
    # either one match.
    domains = [canonical_domain.presence, Company.canonical_domain_for(main_url)].compact_blank.uniq
    core = core_key(name)

    {
      id: id,
      name: name,
      main_url: main_url,
      visible: visible,
      quality_status: quality_status,
      domains: domains,
      final_domain: Company.canonical_domain_for(final_url),
      normalized: normalized,
      core: core,
      brand_keys: ([core] + domains.map { |domain| brand_key(domain) }).compact_blank.uniq,
      profiles: profile_keys("linkedin_url" => linkedin_url, "crunchbase_url" => crunchbase_url),
      historical_names: historical_name_values(slug: slug, prior_names: prior_names, current_normalized: normalized)
    }
  end
end
