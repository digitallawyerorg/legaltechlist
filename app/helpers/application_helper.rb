module ApplicationHelper
  def visible_company_count
    Rails.cache.fetch("companies/visible_count/#{Company.maximum(:updated_at)&.to_i}", expires_in: 10.minutes) do
      Company.where(visible: true).count
    end
  end

  def category_icon(category_name)
    case category_name.downcase
    when /analytics/ then 'fa fa-chart-bar'
    when /compliance/ then 'fa fa-shield'
    when /contract/ then 'fa fa-file-contract'
    when /document/ then 'fa fa-folder'
    when /research/ then 'fa fa-book'
    when /litigation/ then 'fa fa-scale-balanced'
    when /operations/ then 'fa fa-building'
    when /collaboration/ then 'fa fa-users'
    when /ai|emerging/ then 'fa fa-microchip'
    when /talent|people/ then 'fa fa-user-plus'
    when /marketplace/ then 'fa fa-briefcase'
    when /ip|intellectual/ then 'fa fa-lightbulb'
    when /process/ then 'fa fa-gears'
    when /dei|diversity/ then 'fa fa-users-between-lines'
    when /security/ then 'fa fa-lock'
    else 'fa fa-cube'
    end
  end

  def growth_indicator_class(rate)
    return 'text-muted' if rate.nil?

    case rate
    when 0..20
      'text-danger'
    when 20..40
      'text-warning'
    when 40..60
      'text-info'
    when 60..80
      'text-primary'
    else
      'text-success'
    end
  end

  def maturity_stage_class(stage)
    case stage
    when 'Emerging'
      'badge bg-info'
    when 'Growing'
      'badge bg-success'
    when 'Established'
      'badge bg-primary'
    when 'Mature'
      'badge bg-dark'
    else
      'badge bg-secondary'
    end
  end

  def tag_cloud(tags, classes)
    return if tags.empty?

    max = tags.max_by(&:count)
    min = tags.min_by(&:count)
    spread = max.count - min.count + 1

    tags.each do |tag|
      index = if spread == 1
        0
      else
        ((tag.count - min.count) / spread.to_f * (classes.size - 1)).round
      end
      yield(tag, classes[index])
    end
  end

  def growth_rate_class(rate)
    return 'text-muted' if rate.nil?
    if rate > 0
      'badge badge-sm bg-danger-subtle text-danger'
    elsif rate < 0
      'badge badge-sm bg-success-subtle text-success'
    else
      'text-muted'
    end
  end

  def growth_rate_content(rate)
    return 'N/A' if rate.nil?
    prefix = rate > 0 ? '+' : ''
    "#{prefix}#{rate.round(1)}%"
  end
end
