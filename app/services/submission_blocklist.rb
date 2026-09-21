# Curated intake blocklist for public submissions, loaded from
# config/spam/submission_blocklist.yml so a known-spam entry can be added without
# a code change. Two axes: the registrable domain of the submitted URL, and link
# hosts appearing anywhere in the submitted text (payload shortlinks, opt-out
# footers), which is where the same operator is recognisable across submissions.
class SubmissionBlocklist
  PATH = "config/spam/submission_blocklist.yml".freeze

  # Dots are obfuscated to dodge link scanners; the same footer arrived twice as
  # "brnd .li/delist". Normalized away before matching.
  OBFUSCATED_DOT = /\s*(?:\.|\(\s*dot\s*\)|\[\s*dot\s*\]|\s+dot\s+)\s*/

  def self.domains
    entries["domains"]
  end

  def self.link_hosts
    entries["link_hosts"]
  end

  # The blocked domain the submitted URL belongs to, or nil. Subdomains match;
  # a longer domain that merely ends in the same letters does not.
  def self.blocked_domain_for(url)
    domain = Company.canonical_domain_for(url)
    return nil if domain.blank?

    domains.find { |blocked| domain == blocked || domain.end_with?(".#{blocked}") }
  end

  # The blocked link host appearing in free text, or nil. Matched on host
  # boundaries so "notbrnd.link" and "mybrnd.limited" do not hit "brnd.li".
  def self.blocked_link_host_in(text)
    blob = normalize_dots(text)
    return nil if blob.blank?

    link_hosts.find { |host| blob.match?(/(?<![a-z0-9.\-])#{Regexp.escape(host)}(?![a-z0-9\-])/) }
  end

  def self.normalize_dots(text)
    text.to_s.downcase.gsub(OBFUSCATED_DOT, ".")
  end

  def self.entries
    @entries ||= begin
      data = YAML.safe_load(File.read(Rails.root.join(PATH)), permitted_classes: [], aliases: true) || {}
      { "domains" => host_list(data["domains"]), "link_hosts" => host_list(data["link_hosts"]) }
    end
  end

  def self.host_list(values)
    Array(values).map { |value| value.to_s.strip.downcase.sub(/\Awww\./, "") }.compact_blank.freeze
  end
end
