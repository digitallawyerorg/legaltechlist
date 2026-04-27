if defined?(RubyLLM)
  RubyLLM.configure do |config|
    config.openai_api_key = ENV["OPENAI_API_KEY"]
    config.default_model = ENV.fetch("RUBYLLM_DEFAULT_MODEL", ENV.fetch("RUBYLLM_EASY_MODEL", "gpt-5.4-mini"))
    config.request_timeout = ENV.fetch("RUBYLLM_REQUEST_TIMEOUT", Rails.env.production? ? "120" : "30").to_i
    config.max_retries = ENV.fetch("RUBYLLM_MAX_RETRIES", "2").to_i
    config.logger = Rails.logger
    config.log_level = Rails.env.production? ? :info : :warn
  end
end
