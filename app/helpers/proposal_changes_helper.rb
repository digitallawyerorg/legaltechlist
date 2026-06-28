module ProposalChangesHelper
  DISPLAY_ORDER = %w[
    name main_url location founded_date status description
    category_id secondary_category_id
    business_model_ids business_model_id target_client_ids target_client_id all_tags
    crunchbase_url linkedin_url total_funding_amount_usd funding_status
    number_of_funding_rounds founders source source_url
  ].freeze

  def proposal_change_label(field)
    case field
    when "category_id" then "Category"
    when "secondary_category_id" then "Secondary category"
    when "business_model_id", "business_model_ids" then "Revenue models"
    when "target_client_id", "target_client_ids" then "Target clients"
    when "all_tags" then "Tags"
    else field.humanize
    end
  end

  def proposal_change_value(changes, field)
    value = changes[field]
    return if value.blank?

    case field
    when "category_id", "secondary_category_id"
      Category.find_by(id: value)&.name || value
    when "business_model_id"
      BusinessModel.find_by(id: value)&.name || value
    when "business_model_ids"
      BusinessModel.where(id: Array(value).map(&:to_i)).order(:name).pluck(:name).join(", ").presence
    when "target_client_id"
      TargetClient.find_by(id: value)&.name || value
    when "target_client_ids"
      TargetClient.where(id: Array(value).map(&:to_i)).order(:name).pluck(:name).join(", ").presence
    else
      value
    end
  end

  def proposal_changes_for_display(changes)
    shown = {}
    DISPLAY_ORDER.each do |field|
      next if field == "business_model_id" && changes["business_model_ids"].present?
      next if field == "target_client_id" && changes["target_client_ids"].present?

      label = proposal_change_label(field)
      next if shown.key?(label)

      display_value = proposal_change_value(changes, field)
      next if display_value.blank?

      shown[label] = display_value
    end
    shown
  end

  def proposal_suggestion_diffs(proposal)
    baseline = proposal.proposed_changes || {}
    current = proposal.final_changes || {}
    diffs = []

    DISPLAY_ORDER.each do |field|
      next if field == "business_model_id" && (current["business_model_ids"].present? || baseline["business_model_ids"].present?)
      next if field == "target_client_id" && (current["target_client_ids"].present? || baseline["target_client_ids"].present?)
      next unless baseline.key?(field) || current.key?(field)

      old_value = proposal_change_value(baseline, field)
      new_value = proposal_change_value(current, field)
      next if old_value.to_s == new_value.to_s

      label = proposal_change_label(field)
      next if diffs.any? { |diff| diff[:label] == label }

      diffs << { label: label, old_value: old_value, new_value: new_value }
    end

    diffs
  end
end
