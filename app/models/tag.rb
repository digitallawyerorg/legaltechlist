class Tag < ActiveRecord::Base
  has_many :taggings, dependent: :destroy
  has_many :companies, through: :taggings

  # Full curated vocabulary (config/taxonomy/tag_aliases.yml roots).
  def self.canonical_names
    TagTaxonomyService.canonical_root_names
  end

  # Tags suitable for discovery/filtering beyond structured taxonomy fields.
  def self.discoverable_names
    TagTaxonomyService.discoverable_canonical_names
  end

  scope :discoverable, -> { where(name: discoverable_names).order(:name) }

  def self.discoverable_for_form
    discoverable_names.map { |name| find_or_create_by!(name: name) }
  end

  def self.counts
    Tag.select("tags.id, tags.name, count(taggings.tag_id) as count"). joins(:taggings).group("taggings.tag_id, tags.id, tags.name")
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id name created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[taggings companies]
  end
end
