class SubmissionRateLimiter
  HOURLY_LIMIT = 5
  DAILY_LIMIT = 15
  EMAIL_HOURLY_LIMIT = 3
  EMAIL_DAILY_LIMIT = 10

  def self.allow?(ip:, action:, email: nil)
    new(ip: ip, action: action, email: email).allow?
  end

  def initialize(ip:, action:, email: nil)
    @ip = ip.to_s.presence || "unknown"
    @action = action.to_s
    @email = normalize_email(email)
  end

  def allow?
    ip_allowed? && email_allowed?
  end

  def record!
    Rails.cache.write(ip_hourly_key, ip_hourly_count + 1, expires_in: 1.hour)
    Rails.cache.write(ip_daily_key, ip_daily_count + 1, expires_in: 24.hours)
    return if email.blank?

    Rails.cache.write(email_hourly_key, email_hourly_count + 1, expires_in: 1.hour)
    Rails.cache.write(email_daily_key, email_daily_count + 1, expires_in: 24.hours)
  end

  private

  attr_reader :ip, :action, :email

  def ip_allowed?
    ip_hourly_count < HOURLY_LIMIT && ip_daily_count < DAILY_LIMIT
  end

  def email_allowed?
    return true if email.blank?

    email_hourly_count < EMAIL_HOURLY_LIMIT && email_daily_count < EMAIL_DAILY_LIMIT
  end

  def ip_hourly_count
    Rails.cache.read(ip_hourly_key).to_i
  end

  def ip_daily_count
    Rails.cache.read(ip_daily_key).to_i
  end

  def email_hourly_count
    Rails.cache.read(email_hourly_key).to_i
  end

  def email_daily_count
    Rails.cache.read(email_daily_key).to_i
  end

  def ip_hourly_key
    "submission_rate:#{action}:#{ip}:hour"
  end

  def ip_daily_key
    "submission_rate:#{action}:#{ip}:day"
  end

  def email_hourly_key
    "submission_rate:#{action}:email:#{email}:hour"
  end

  def email_daily_key
    "submission_rate:#{action}:email:#{email}:day"
  end

  def normalize_email(value)
    value.to_s.strip.downcase.presence
  end
end
