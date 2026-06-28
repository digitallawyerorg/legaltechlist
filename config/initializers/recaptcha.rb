if ENV["RECAPTCHA_SITE_KEY"].present? && ENV["RECAPTCHA_SECRET_KEY"].present?
  Recaptcha.configure do |config|
    config.site_key = ENV["RECAPTCHA_SITE_KEY"]
    config.secret_key = ENV["RECAPTCHA_SECRET_KEY"]
  end
end
