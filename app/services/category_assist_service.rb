class CategoryAssistService
  def self.rules
    @rules ||= YAML.safe_load(
      File.read(Rails.root.join("config/taxonomy/category_assist.yml")),
      permitted_classes: [],
      aliases: true
    )
  end

  def self.call(company:)
    Array(rules).each do |rule|
      next unless signal_match?(company, rule)

      category = Category.find_by(name: rule["target"])
      return { "name" => rule["target"], "confidence" => 0.88, "mode" => "category_assist" } if category
    end

    nil
  end

  def self.signal_match?(company, rule)
    tag_match?(company, rule) || description_match?(company, rule)
  end

  def self.tag_match?(company, rule)
    tag_names = company.tags.map { |tag| tag.name.to_s.downcase }
    Array(rule["tag_patterns"]).any? do |pattern|
      normalized = TagNormalizationService.normalize_name(pattern)
      tag_names.any? { |tag| tag.include?(normalized) || TagNormalizationService.canonical_name(tag) == normalized }
    end
  end

  def self.description_match?(company, rule)
    text = [company.name, company.description].compact.join(" ")
    Array(rule["description_patterns"]).any? { |pattern| text.match?(/#{pattern}/i) }
  end
end
