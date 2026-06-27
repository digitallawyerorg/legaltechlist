if defined?(RubyLLM)
  ActiveSupport::Notifications.subscribe(/\.ruby_llm\z/) do |event_name, start_time, end_time, _event_id, payload|
    duration_ms = ((end_time - start_time) * 1000).round(1)
    safe_payload = {
      event: event_name,
      duration_ms: duration_ms,
      provider: payload[:provider],
      model: payload[:model],
      input_tokens: payload[:input_tokens],
      output_tokens: payload[:output_tokens],
      cache_read_tokens: payload[:cache_read_tokens],
      cache_write_tokens: payload[:cache_write_tokens],
      status: payload[:status],
      tool: payload[:tool]&.class&.name || payload[:tool_name],
      exception: payload[:exception]&.first
    }.compact

    Rails.logger.debug { "RubyLLM event #{safe_payload.to_json}" }
  end
end
