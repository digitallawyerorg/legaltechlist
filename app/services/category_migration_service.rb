class CategoryMigrationService
  def self.crosswalk_config
    @crosswalk_config ||= YAML.safe_load(
      File.read(Rails.root.join("config/taxonomy/crosswalk_v2.yml")),
      permitted_classes: [],
      aliases: true
    )
  end

  def self.call(company:, dry_run: true)
    new(company: company, dry_run: dry_run).call
  end

  def initialize(company:, dry_run: true)
    @company = company
    @dry_run = dry_run
    @config = self.class.crosswalk_config
  end

  def call
    current_name = company.category&.name
    return skip("no_category") if current_name.blank?

    target_name = matched_target_category
    return skip("unchanged") if target_name.blank? || target_name == current_name

    target_category = Category.find_by(name: target_name)
    return skip("missing_target_category") unless target_category

    unless dry_run
      company.update!(category: target_category)
    end

    {
      "company_id" => company.id,
      "company_name" => company.name,
      "from_category" => current_name,
      "to_category" => target_name,
      "action" => dry_run ? "would_migrate" : "migrated"
    }
  end

  private

  attr_reader :company, :dry_run, :config

  def skip(reason)
    {
      "company_id" => company.id,
      "company_name" => company.name,
      "from_category" => company.category&.name,
      "action" => "skipped_#{reason}"
    }
  end

  def matched_target_category
    Array(config["rules"]).each do |rule|
      next unless rule["source_categories"].include?(company.category.name)

      return rule["target"] if tag_match?(rule) || description_match?(rule)
    end

    nil
  end

  def tag_match?(rule)
    tag_names = company.tags.map { |tag| tag.name.to_s.downcase }
    Array(rule["tag_patterns"]).any? do |pattern|
      normalized = TagNormalizationService.normalize_name(pattern)
      tag_names.any? { |tag| tag.include?(normalized) || TagNormalizationService.canonical_name(tag) == normalized }
    end
  end

  def description_match?(rule)
    text = [company.name, company.description].compact.join(" ")
    Array(rule["description_patterns"]).any? { |pattern| text.match?(/#{pattern}/i) }
  end
end
