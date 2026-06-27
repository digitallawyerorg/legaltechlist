class TagNormalizationService
  def self.normalize_name(raw)
    raw.to_s.strip.downcase.gsub(/\s+/, " ")
  end

  def self.alias_map
    @alias_map ||= begin
      path = Rails.root.join("config/taxonomy/tag_aliases.yml")
      data = YAML.safe_load(File.read(path), permitted_classes: [], aliases: true) || {}
      map = {}
      data.each do |canonical, aliases|
        canonical_key = normalize_name(canonical)
        map[canonical_key] = canonical_key
        Array(aliases).each { |alias_name| map[normalize_name(alias_name)] = canonical_key }
      end
      map
    end
  end

  def self.canonical_name(raw)
    key = normalize_name(raw)
    return nil if key.blank?

    alias_map[key] || key
  end

  def self.find_or_create_canonical(raw)
    name = canonical_name(raw)
    return nil if name.blank?

    Tag.find_by("LOWER(name) = ?", name) || Tag.create!(name: name)
  end

  def self.merge_duplicate_tags!(dry_run: true)
    counts = { merged: 0, taggings_moved: 0, tags_removed: 0 }
    groups = Hash.new { |hash, key| hash[key] = [] }

    Tag.find_each do |tag|
      canonical = canonical_name(tag.name)
      groups[canonical] << tag
    end

    groups.each do |canonical, tags|
      next if tags.size <= 1

      keeper = tags.min_by(&:id)
      if keeper.name != canonical && !dry_run
        keeper.update!(name: canonical)
      end

      tags.reject { |tag| tag.id == keeper.id }.each do |duplicate|
        counts[:merged] += 1
        duplicate.taggings.find_each do |tagging|
          unless Tagging.exists?(tag_id: keeper.id, company_id: tagging.company_id)
            counts[:taggings_moved] += 1
            tagging.update!(tag_id: keeper.id) unless dry_run
          else
            tagging.destroy! unless dry_run
          end
        end
        counts[:tags_removed] += 1
        duplicate.destroy! unless dry_run
      end
    end

    counts
  end
end
