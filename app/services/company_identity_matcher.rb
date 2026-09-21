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
# Every key means a human may want to compare two records. It does not follow that every
# key may stop a write: "Needs revision · matched on brand name · created first" was one
# weak key, read off a citation host neither record owns, worded exactly like a confirmed
# duplicate. So each hit is also SURFACED — blocking when one key can carry the claim
# alone or two independent evidence families agree, advisory otherwise. Advisory hits are
# still computed, still reported with every key that fired, still graded and still
# recorded; they just no longer assert a duplicate by themselves. Nothing is deleted
# here, only demoted. Comparison is still the point.
class CompanyIdentityMatcher
  CACHE_TTL = 5.minutes
  # Bumped whenever an index row gains a key. A row cached in the previous shape is
  # missing the new one, which silently turns the new match type off until it expires.
  CACHE_SHAPE = "v4".freeze

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

  # ---- surfacing ----------------------------------------------------------
  #
  # A key says two records *may* be the same. Surfacing says whether the evidence is
  # strong enough to stop a write on its own.
  #
  #   blocking  at least one key that can carry a duplicate claim alone, or keys from two
  #             independent evidence families.
  #   advisory  keys agreed, but all of them are weak and all of them are reading the
  #             same thing. The hit is still reported, still graded and still recorded;
  #             it just does not assert a duplicate by itself.
  #
  # Nothing is deleted here. Every key that fired before still fires, still appears in
  # match_types and still reaches the reviewer. "Needs revision - matched on brand name"
  # was one weak key stopping a write, and the answer is to say how far that key goes,
  # not to stop computing it.
  SURFACING_BLOCKING = "blocking".freeze
  SURFACING_ADVISORY = "advisory".freeze

  # Evidence families, assigned by PROVENANCE rather than by key name. Two keys
  # corroborate each other only when they are independent readings: a brand label read
  # off both records' domains is a restatement of a domain agreement, not a second
  # opinion about the name, so it sits with the domains.
  FAMILY_ADDRESS = "address".freeze
  FAMILY_PROFILE = "profile".freeze
  FAMILY_NAME = "name".freeze

  # Three states on purpose. "shared" is a measurement that came out negative;
  # "unevaluated" is a measurement that could not be taken, which is not the same thing
  # and must never be read as one. A tenant subdomain on a shared host publishes no
  # readable brand label at all (brand_key is nil there by design), and an absent label
  # is not evidence that two records are different companies.
  OWNERSHIP_OWNED = "owned".freeze
  OWNERSHIP_SHARED = "shared".freeze
  OWNERSHIP_UNEVALUATED = "unevaluated".freeze

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

  # Aggregators, registries, social networks and link-in-bio pages. A record whose
  # website or citation URL is one of these is not giving its own address: it is pointing
  # at somebody else's page about it, and every other record on that host is pointing at a
  # page about somebody else. Read as identity, the host becomes the shared address of
  # every record discovery ever cited from it — the duplicate panels on proposals 4179 and
  # 4378 both named the unrelated proposal 3827 (Tecnika Legal), "matched on brand name",
  # because the brand label read off a crunchbase.com citation is "crunchbase" on all
  # three of them.
  #
  # The registry and profile hosts are the ones CompanyProposalEnrichmentService already
  # names, so a host means the same thing in both places; the rest are the social and
  # link-in-bio pages a submission carries when it has no site of its own.
  #
  # This is not SHARED_HOSTS. Those hand out a subdomain per tenant, so the tenant label
  # is still an identity and only the platform's own label is not. Here the whole host
  # belongs to someone else, so no domain key may be read from it at all.
  NON_IDENTIFYING_HOSTS = (
    CompanyProposalEnrichmentService::ENTITY_REGISTRY_HOSTS + %w[
      facebook.com instagram.com x.com twitter.com youtube.com
      linktr.ee sites.google.com medium.com
    ]
  ).freeze

  # True for one of those hosts and for anything under it.
  def self.non_identifying_host?(domain)
    host = domain.to_s.downcase.delete_suffix(".")
    return false if host.blank?

    NON_IDENTIFYING_HOSTS.any? { |entry| host == entry || host.end_with?(".#{entry}") }
  end

  # The subset of a record's domains that may stand for the record itself. Filtering one
  # side of a domain comparison is enough to filter both: an element dropped here cannot
  # survive in an intersection with the other side.
  def self.identifying_domains(values)
    Array(values).reject { |domain| non_identifying_host?(domain) }
  end

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

  # PROFILE_PATH_ROOTS says which paths name a company; this says which SITES do.
  # The same two hosts CompanyProposalEnrichmentService already names, so a host means
  # one thing in both places.
  PROFILE_KIND_HOSTS = CompanyProposalEnrichmentService::PROFILE_HOSTS
                       .index_with { |host| host.split(".").first }.freeze

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

  # The brand a record calls itself, read as a COMPONENT of its name rather than as the
  # whole of it. Real submissions carry the brand inside a longer name - a parenthetical
  # product, an "X by Y", a vendor plus a product - and the whole-name core of
  # "White Rabbit (Deep-Law)" is "whiterabbitdeeplaw", which names no brand anyone else
  # can carry. Reading the segments as well is what keeps public company 16479
  # (D-Developments at deep-law.io) reachable from proposal 4139.
  #
  # Only separators that actually separate: a hyphen inside a word is part of the brand
  # ("Deep-Law", "D-Developments"), a hyphen with spaces around it is punctuation.
  NAME_SEGMENT_PATTERN = %r{[()\[\]{}|,:;/]|\s[-\u2013\u2014]\s|\s+by\s+}i

  def self.name_segments(value)
    value.to_s.split(NAME_SEGMENT_PATTERN).map(&:strip).compact_blank
  end

  # Every brand string this record CALLS ITSELF: the whole-name core and each segment's.
  # Used to decide provenance, never to decide what matches - widening the match keys
  # here would invent matches rather than grade the ones already found.
  def self.name_keys(value)
    ([core_key(value)] + name_segments(value).map { |segment| core_key(segment) }).compact_blank.uniq
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
    # A Crunchbase or LinkedIn page carries the aggregator's brand, never the record's.
    return nil if non_identifying_host?(host)

    labels = host.split(".")
    suffix_labels = REGISTRY_SUFFIXES.any? { |suffix| host.end_with?(".#{suffix}") } ? 2 : 1
    registrable = labels.last(suffix_labels + 1).join(".")
    # On a host that hands out tenant subdomains the registrable label is the platform's,
    # not the tenant's, so reading it as a brand would give every tenant the same one.
    return nil if registrable.in?(SHARED_HOSTS)

    core_key(labels[-(suffix_labels + 1)])
  end

  # linkedin.com, crunchbase.com, or a subdomain of either. Anything else is not a
  # company page however its path is spelled.
  def self.profile_kind_for(host)
    host = host.to_s.downcase.delete_suffix(".")
    return nil if host.blank?

    PROFILE_KIND_HOSTS.each { |entry, kind| return kind if host == entry || host.end_with?(".#{entry}") }
    nil
  end

  # The company page a URL names. The kind is read from the HOST, not from the field the
  # URL was sitting in: a Crunchbase link pasted into linkedin_url is a Crunchbase page,
  # and a /company/<slug> path on any other site is not a company page at all. Before
  # this check the path alone minted the key, so two records whose linkedin_url happened
  # to be some vendor's own /company/team page shared a key graded "confirmed" - the one
  # key in the system that asserts a duplicate with nothing else agreeing.
  def self.profile_key_for(url)
    uri = URI.parse(url.to_s.strip)
    kind = profile_kind_for(uri.host)
    return nil if kind.blank?

    segments = uri.path.to_s.downcase.split("/").reject(&:blank?)
    return nil unless segments.first.in?(PROFILE_PATH_ROOTS.fetch(kind, []))

    key = segments[1].to_s
    return nil if key.length < MIN_PROFILE_KEY_LENGTH || key.in?(GENERIC_PROFILE_KEYS)

    "#{kind}:#{key}"
  rescue URI::Error
    nil
  end

  # For a reader that already knows which kind it is asking about.
  def self.profile_key(kind, url)
    key = profile_key_for(url)
    key if key.present? && key.start_with?("#{kind}:")
  end

  # The kind is read from the host, so a Crunchbase URL pasted into linkedin_url is a
  # Crunchbase page. It must not DISPLACE the record's own crunchbase_url, though: first
  # come first served dropped the correctly-filed page and the misfiled field's own kind
  # at once, and shared_profile is the only always-alone-eligible key in the system, so a
  # dropped one is a true duplicate lost. The entry whose derived kind is the field it
  # came from wins; a misfiled one only fills a gap.
  def self.profile_keys(source)
    found = PROFILE_KINDS.filter_map do |field|
      key = profile_key_for(source["#{field}_url"])
      [field, key, key.split(":").first] if key.present?
    end

    found.each_with_object({}) do |(field, key, derived), keys|
      keys[derived] = key if field == derived || !keys.key?(derived)
    end
  end

  # True when one host sits under the other by an entrance label — the same company
  # reached a different way. Refused on shared hosts, on a bare suffix, and on any label
  # that could be a tenant name.
  def self.related_domains?(one, other)
    return false if one.blank? || other.blank? || one == other
    # Two pages on one aggregator are two companies, however they nest.
    return false if non_identifying_host?(one) || non_identifying_host?(other)

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

    expand_name_values(candidates, current_normalized)
  end

  def self.expand_name_values(candidates, current_normalized)
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

  # How far the evidence goes, for any two records compared on these keys. The
  # proposal-to-proposal comparison grades through here too: sibling proposals used to be
  # reported ungraded, so the reviewer-facing text asserted sameness on a shared domain
  # alone — and Europaius 4113/4114 and Epistemic Labs 4102/4103 were one company with two
  # genuinely distinct products. One grading rule, both sides.
  def self.confidence_for(match_type, names_agree:, shared_profile:)
    case match_type
    when "redirect_domain", "shared_profile"
      CONFIDENCE_CONFIRMED
    when "exact_domain", "related_domain"
      # One domain, and one domain tree, can host more than one product. Treat it as
      # confirmed only when the names agree too; otherwise say it may be a sibling.
      names_agree ? CONFIDENCE_CONFIRMED : CONFIDENCE_POSSIBLE
    else
      shared_profile ? CONFIDENCE_CONFIRMED : CONFIDENCE_POSSIBLE
    end
  end

  # Each side is {normalized:, core:}. Either key agreeing is the names agreeing.
  def self.names_agree?(one, other)
    return true if one[:normalized].present? && one[:normalized] == other[:normalized]

    one[:core].present? && one[:core] == other[:core]
  end

  # ---- surfacing ----------------------------------------------------------

  # Is the shared domain an address one of these two records OWNS, or one they merely
  # both happen to sit on?
  #
  # This is the general replacement for "is this host on the aggregator list". A list
  # says what fifteen hosts are; this asks what the population shows, so play.google.com,
  # producthunt.com, wellfound.com, github.com and the next one nobody has listed yet are
  # all answered by the same test. Two readings, either of which is enough:
  #
  #   * the domain's brand label is a name one of the two records calls itself
  #     (caseway.ai / "Caseway", pactolane.com / "Pactolane"), or
  #   * no OTHER record in the compared population carries that domain, so there is no
  #     evidence it is a place records get put rather than an address.
  #
  # +other_carriers+ counts records other than the two being compared, over the index
  # AND the open queue together.
  #
  # An unreadable brand label ends the FIRST reading, not the measurement. Giving up on
  # the whole test there is what made this unable to fire on the hosts that need it most:
  # brand_key is nil for every bare entry in SHARED_HOSTS, so two unrelated records whose
  # canonical domain is wixsite.com itself blocked on exact_domain alone. So the
  # population is still consulted: other carriers present is +shared+ however the label
  # reads, and only a blank label with nobody else on the host stays UNEVALUATED — which
  # is the tenant-subdomain case (marbury-clause.wixsite.com), where an absent label is
  # not evidence that two records are different companies.
  def self.domain_ownership(domain, name_keys:, other_carriers:)
    return OWNERSHIP_UNEVALUATED if domain.blank?

    label = brand_key(domain)
    return OWNERSHIP_OWNED if label.present? && label.in?(Array(name_keys))
    return OWNERSHIP_UNEVALUATED if label.blank? && other_carriers.to_i.zero?

    other_carriers.to_i.zero? ? OWNERSHIP_OWNED : OWNERSHIP_SHARED
  end

  # Only a measured "shared" demotes. Unevaluated is not a negative.
  def self.owned_domain?(state)
    state != OWNERSHIP_SHARED
  end

  # The brand cross: one record CALLS ITSELF this brand and the other publishes it only
  # as its address. That, and only that, is the false negative brand_name was built for
  # (proposal 4139 against D-Developments at deep-law.io), and it is the only shape in
  # which a brand label may assert a duplicate on its own.
  #
  # Each side is {normalized:, name_keys:, brand_domain_keys:}.
  def self.brand_cross?(key, one, other)
    brand_cross_one_way?(key, one, other) || brand_cross_one_way?(key, other, one)
  end

  # Refused when the side that supposedly only publishes the brand as an address in fact
  # begins its own name with it: "Harvey Law Group" at harvey.com.hk does call itself
  # Harvey, it just calls itself Harvey plus two more words, and reading that as "only
  # publishes it as an address" is how an unrelated Hong Kong firm becomes an
  # alone-eligible duplicate of a US legal-AI vendor.
  def self.brand_cross_one_way?(key, naming, addressing)
    return false if key.blank?
    return false unless Array(naming[:name_keys]).include?(key)
    return false if Array(addressing[:name_keys]).include?(key)
    return false unless Array(addressing[:brand_domain_keys]).include?(key)

    !leading_token_run?(addressing[:normalized], key)
  end

  # True when the normalized name starts with the key as a whole run of leading tokens:
  # "harvey law group" starts with "harvey", "d developments" does not start with
  # "deeplaw", "unison labs" does not start with "sixminute".
  def self.leading_token_run?(normalized, key)
    run = +""
    normalized.to_s.split.any? do |token|
      run << token
      run == key
    end
  end

  # Every key that fired on one pair, with the family it belongs to and whether it can
  # carry a duplicate claim on its own.
  #
  #   sides          [candidate, other], each {normalized:, name_keys:, brand_domain_keys:}
  #   domain_states  ownership state per domain key, from domain_ownership
  #   brand_key      the shared brand label, when brand_name fired
  def self.evidence_for(match_types, sides:, domain_states: {}, brand_key: nil)
    Array(match_types).map do |type|
      family, alone =
        case type
        # A resolved redirect is a fact about where one site sends its visitors, not
        # evidence of co-tenancy, which is the only thing the ownership test measures.
        # Putting it under that test let a confirmed redirect report itself confirmed and
        # advisory in one breath, because the target host happened to carry other records.
        when "redirect_domain" then [FAMILY_ADDRESS, true]
        when *DOMAIN_MATCH_TYPES
          [FAMILY_ADDRESS, owned_domain?(domain_states[type])]
        when "shared_profile" then [FAMILY_PROFILE, true]
        when "exact_name" then [FAMILY_NAME, true]
        # Alone-eligible however the prior name was recovered. Requiring a rename recorded
        # in the edit history read an absent record as evidence that two records are
        # DIFFERENT companies, which is the same mistake the ownership test refuses to
        # make about domains — and it silently demoted the real eSignLive/OneSpan rebrand,
        # whose only trace of the old name is the slug.
        when "prior_name" then [FAMILY_NAME, true]
        when "core_name" then [FAMILY_NAME, false]
        when "brand_name" then brand_evidence(brand_key, sides)
        else [FAMILY_NAME, false]
        end

      { "key" => type, "family" => family, "alone" => alone }
    end
  end

  # Ordered, because the two shapes overlap: a key can be a cross AND be domain-derived
  # on both sides (a row naming Deep Law at deep-law.io, against a record at
  # deep-law.com). The cross is the stronger statement, so it is read first.
  def self.brand_evidence(key, sides)
    return [FAMILY_NAME, false] if key.blank?
    return [FAMILY_NAME, true] if brand_cross?(key, *sides)
    return [FAMILY_ADDRESS, false] if sides.all? { |side| Array(side[:brand_domain_keys]).include?(key) }

    [FAMILY_NAME, false]
  end

  # One alone-eligible key, or two independent families agreeing. Anything else is a
  # single loose match, which is reported rather than enforced.
  def self.surfacing_for(evidence)
    return nil if evidence.blank?
    return SURFACING_BLOCKING if evidence.any? { |item| item["alone"] }
    return SURFACING_BLOCKING if evidence.map { |item| item["family"] }.uniq.size > 1

    SURFACING_ADVISORY
  end

  # MAX_MATCHES is a display cap, and a display cap must not change a verdict. Ten
  # advisory hits of a higher-precedence key would otherwise crowd out the eleventh,
  # blocking one, and the caller's "any blocking?" would read the truncated list and
  # answer no. Blocking hits are kept first; the reported ORDER is still precedence.
  def self.capped(hits)
    return hits if hits.size <= MAX_MATCHES

    keep = hits.select { |hit| hit["surfacing"] == SURFACING_BLOCKING }.first(MAX_MATCHES)
    hits.each do |hit|
      break if keep.size >= MAX_MATCHES

      keep << hit unless keep.any? { |kept| kept.equal?(hit) }
    end
    hits.select { |hit| keep.any? { |kept| kept.equal?(hit) } }
  end

  def self.matches_for(name:, domains: [], declared_domains: nil, profiles: {}, exclude_company_id: nil)
    new(name: name, domains: domains, declared_domains: declared_domains, profiles: profiles, exclude_company_id: exclude_company_id).matches
  end

  # extra_domain_carriers is how a caller folds ITS OWN population into the ownership
  # measurement: {domain => number of records}. The proposal detector passes the open
  # queue, so one domain gets one verdict per call instead of reading "owned" on the
  # sibling side and "shared" on the company side of the very same pair.
  def initialize(name:, domains: [], declared_domains: nil, profiles: {}, exclude_company_id: nil, extra_domain_carriers: {})
    @name = name
    @domains = normalize_domains(domains)
    @declared_domains = normalize_domains(declared_domains.nil? ? domains : declared_domains)
    @profiles = profiles.to_h.compact_blank
    @exclude_company_id = exclude_company_id
    @extra_domain_carriers = extra_domain_carriers.to_h
  end

  def matches
    return [] if normalized_name.blank? && domains.empty? && profiles.empty?

    self.class.index.filter_map do |row|
      next if exclude_company_id.present? && row[:id] == exclude_company_id

      match_types = match_types_for(row)
      next if match_types.empty?

      match_type = match_types.first
      domain_states = domain_states_for(match_types, row)
      evidence = evidence_for(match_types, row, domain_states)
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
        # How far this pair goes: "blocking" stops a write, "advisory" is reported and
        # recorded but asserts nothing on its own. Every key still appears above either
        # way - a demoted key is still a comparison a reviewer may want to make.
        "surfacing" => self.class.surfacing_for(evidence),
        "shared_profiles" => shared_profiles(row)
      }.merge(domain_states.any? ? { "domain_ownership" => domain_states.values.first } : {})
    end.then { |hits| self.class.capped(hits.sort_by { |hit| MATCH_TYPES.index(hit["match_type"]) }) }
  end

  # True when the matched domain is one we only learned by resolving the candidate's site,
  # or one it never declared — the signature of a rebrand rather than a resubmission.
  def rebrand?(hit)
    return true if hit["match_type"] == "redirect_domain"

    hit["match_type"].in?(%w[exact_domain related_domain]) &&
      hit["matched_value"].present? && !declared_domains.include?(hit["matched_value"])
  end

  attr_reader :declared_domains

  # The whole compared population, domain by domain: every record in the index plus
  # whatever the caller folded in. Public because the caller grading its own population
  # has to count over the same union, or the two sides disagree about one pair.
  def domain_carriers
    @domain_carriers ||= self.class.index.each_with_object(Hash.new(0)) do |row, counts|
      row[:domains].uniq.each { |domain| counts[domain] += 1 }
    end.tap do |counts|
      extra_domain_carriers.each { |domain, extra| counts[domain] += extra.to_i }
    end
  end

  # The candidate's own already-minted company is not a third party on any host.
  def excluded_row_domains
    @excluded_row_domains ||= if exclude_company_id.present?
      Array(self.class.index.find { |row| row[:id] == exclude_company_id }&.fetch(:domains, nil))
    else
      []
    end
  end

  private

  attr_reader :name, :domains, :profiles, :exclude_company_id, :extra_domain_carriers

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
  # The domains that may stand for this candidate. See NON_IDENTIFYING_HOSTS: two records
  # both cited from Crunchbase share a host, not an address.
  def identity_domains
    @identity_domains ||= self.class.identifying_domains(domains)
  end

  def brand_keys
    @brand_keys ||= ([core_key] + brand_domain_keys).compact_blank.uniq
  end

  # The brand labels this candidate publishes as an ADDRESS, kept apart from the one it
  # carries in its name. Which of the two a shared brand key came from is the whole
  # difference between a brand cross and two records on one host.
  def brand_domain_keys
    @brand_domain_keys ||= domains.filter_map { |domain| self.class.brand_key(domain) }.uniq
  end

  def candidate_side
    @candidate_side ||= {
      normalized: normalized_name,
      name_keys: self.class.name_keys(name),
      brand_domain_keys: brand_domain_keys
    }
  end

  def row_side(row)
    { normalized: row[:normalized], name_keys: Array(row[:name_keys]), brand_domain_keys: Array(row[:brand_domain_keys]) }
  end

  def evidence_for(match_types, row, domain_states)
    self.class.evidence_for(
      match_types,
      sides: [candidate_side, row_side(row)],
      domain_states: domain_states,
      brand_key: brand_match_for(row)
    )
  end

  def domain_states_for(match_types, row)
    (match_types & DOMAIN_MATCH_TYPES).index_with do |type|
      value = matched_value_for(type, row)
      self.class.domain_ownership(
        value,
        name_keys: candidate_side[:name_keys] + Array(row[:name_keys]),
        other_carriers: other_carriers_for(value, row)
      )
    end
  end

  # Records OTHER than the two being compared that carry this domain. The population is
  # the index, which is already in memory; the candidate is not in it, except when it is
  # the row it excludes itself against.
  def other_carriers_for(domain, row)
    return 0 if domain.blank?

    count = domain_carriers[domain].to_i
    count -= 1 if row[:domains].include?(domain)
    count -= 1 if excluded_row_domains.include?(domain)
    [count, 0].max
  end

  def match_types_for(row)
    types = []
    types << "exact_domain" if (identity_domains & row[:domains]).any?
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
    when "exact_domain" then (identity_domains & row[:domains]).first
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
    self.class.confidence_for(
      match_type,
      names_agree: self.class.names_agree?({ normalized: normalized_name, core: core_key }, row),
      shared_profile: shared_profiles(row).any?
    )
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
      # Carried separately from brand_keys, which mixes both provenances on purpose so
      # that a name can meet a domain. Grading the hit needs to know which was which.
      brand_domain_keys: domains.filter_map { |domain| brand_key(domain) }.uniq,
      name_keys: name_keys(name),
      profiles: profile_keys("linkedin_url" => linkedin_url, "crunchbase_url" => crunchbase_url),
      historical_names: historical_name_values(slug: slug, prior_names: prior_names, current_normalized: normalized)
    }
  end
end
