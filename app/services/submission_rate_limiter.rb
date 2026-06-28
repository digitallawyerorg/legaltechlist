class SubmissionRateLimiter
  HOURLY_LIMIT = 5
  DAILY_LIMIT = 20

  def self.allow?(ip:, action:)
    new(ip: ip, action: action).allow?
  end

  def initialize(ip:, action:)
    @ip = ip.to_s.presence || "unknown"
    @action = action.to_s
  end

  def allow?
    hourly_count < HOURLY_LIMIT && daily_count < DAILY_LIMIT
  end

  def record!
    Rails.cache.write(hourly_key, hourly_count + 1, expires_in: 1.hour)
    Rails.cache.write(daily_key, daily_count + 1, expires_in: 24.hours)
  end

  private

  attr_reader :ip, :action

  def hourly_count
    Rails.cache.read(hourly_key).to_i
  end

  def daily_count
    Rails.cache.read(daily_key).to_i
  end

  def hourly_key
    "submission_rate:#{action}:#{ip}:hour"
  end

  def daily_key
    "submission_rate:#{action}:#{ip}:day"
  end
end
