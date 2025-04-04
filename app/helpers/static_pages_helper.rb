module StaticPagesHelper
  def success_rate_class(rate)
    if rate > 50
      'text-success'
    elsif rate < 20
      'text-danger'
    else
      'text-warning'
    end
  end

  def exit_rate_class(rate)
    if rate > 15
      'text-success'
    elsif rate < 5
      'text-danger'
    else
      'text-warning'
    end
  end

  def growth_class(growth)
    if growth > 20
      'text-success'
    elsif growth < 0
      'text-danger'
    else
      'text-warning'
    end
  end

  def growth_pattern_class(pattern)
    case pattern
    when 'Venture-Backed'
      'badge.badge-success'
    when 'Mixed'
      'badge.badge-info'
    when 'Single Round'
      'badge.badge-warning'
    when 'Bootstrap'
      'badge.badge-secondary'
    else
      'badge.badge-light'
    end
  end
end
