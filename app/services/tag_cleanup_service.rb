class TagCleanupService
  def self.call(dry_run: true)
    new(dry_run: dry_run).call
  end

  def initialize(dry_run: true)
    @dry_run = dry_run
  end

  def call
    merge_counts = TagNormalizationService.merge_duplicate_tags!(dry_run: dry_run)
    redundant_counts = remove_redundant_taggings!
    orphan_counts = remove_orphan_tags!

    merge_counts.merge(redundant_counts).merge(orphan_counts).merge("dry_run" => dry_run)
  end

  private

  attr_reader :dry_run

  def remove_redundant_taggings!
    counts = { redundant_taggings_removed: 0, companies_affected: 0, redundant_tags: [] }

    Tag.joins(:taggings).distinct.find_each do |tag|
      canonical = TagNormalizationService.canonical_name(tag.name)
      next if TagTaxonomyService.discoverable_canonical_names.include?(canonical)
      next unless TagTaxonomyService.redundant_with_taxonomy?(tag.name)

      taggings = tag.taggings.to_a
      next if taggings.empty?

      counts[:redundant_tags] << tag.name
      counts[:redundant_taggings_removed] += taggings.size
      counts[:companies_affected] += taggings.map(&:company_id).uniq.size

      taggings.each { |tagging| tagging.destroy! } unless dry_run
    end

    counts[:redundant_tags] = counts[:redundant_tags].sort
    counts
  end

  def remove_orphan_tags!
    orphans = Tag.left_joins(:taggings).where(taggings: { id: nil })
    count = orphans.count
    orphans.destroy_all unless dry_run
    { orphan_tags_removed: count }
  end
end
