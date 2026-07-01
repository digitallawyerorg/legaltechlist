# Slack notifications for user contributions and suggestions.
# Configure SLACK_BOT_TOKEN and SLACK_CHANNEL_ID (e.g. #rover-techindex) for API thread replies.
# SLACK_WEBHOOK_URL is supported as a fallback without thread replies.
require "net/http"
require "json"

class SlackNotifier
  API_URL = "https://slack.com/api/chat.postMessage"
  BOT_TOKEN = ENV["SLACK_BOT_TOKEN"]
  CHANNEL_ID = ENV["SLACK_CHANNEL_ID"]
  WEBHOOK_URL = ENV["SLACK_WEBHOOK_URL"]

  def self.post_message(text: nil, blocks: nil, channel: CHANNEL_ID)
    if use_api?
      payload = { channel: channel }
      payload[:blocks] = blocks if blocks
      payload[:text] = text || blocks_to_fallback(blocks)
      response = api_post(payload)
      return nil unless response

      data = JSON.parse(response.body)
      data["ok"] ? data["ts"] : (Rails.logger.debug("[SlackNotifier] API error: #{data['error']}"); nil)
    elsif WEBHOOK_URL.present?
      webhook_post(text: text || blocks_to_fallback(blocks))
      nil
    end
  rescue => e
    Rails.logger.debug("[SlackNotifier] post_message failed: #{e.message}")
    nil
  end

  def self.post_thread(thread_ts, text: nil, blocks: nil, channel: CHANNEL_ID)
    return unless use_api? && thread_ts.present?

    payload = { channel: channel, thread_ts: thread_ts }
    payload[:blocks] = blocks if blocks
    payload[:text] = text || blocks_to_fallback(blocks)
    response = api_post(payload)
    return unless response

    data = JSON.parse(response.body)
    Rails.logger.debug("[SlackNotifier] Thread API error: #{data['error']}") unless data["ok"]
  rescue => e
    Rails.logger.debug("[SlackNotifier] post_thread failed: #{e.message}")
  end

  def self.user_contribution_submitted(proposal)
    return unless configured?

    blocks = [
      header("New company contribution"),
      section(":inbox_tray: *#{proposal.display_name}*\nfrom #{proposal.submitter_email}"),
      context(proposal.final_changes["main_url"].presence || "No website")
    ]
    blocks << actions(button("Review proposal", admin_proposal_url(proposal)))

    ts = post_message(blocks: blocks, text: "New company contribution: #{proposal.display_name}")
    proposal.update_column(:slack_message_ts, ts) if ts.present?
    ts
  end

  def self.user_suggestion_submitted(proposal)
    return unless configured?

    company = proposal.company
    blocks = [
      header("Company update suggestion"),
      section(":pencil2: *#{company&.name || proposal.display_name}*\n#{proposal.issue_type.to_s.humanize} · #{proposal.submitter_email}"),
      section(proposal.user_message.to_s.truncate(500))
    ]
    blocks << actions(button("Review proposal", admin_proposal_url(proposal)))

    ts = post_message(blocks: blocks, text: "Update suggestion for #{company&.name}")
    proposal.update_column(:slack_message_ts, ts) if ts.present?
    ts
  end

  def self.contribution_decision(proposal, decision:, admin_user: nil, note: nil)
    return unless configured?

    emoji = decision.to_s == "approved" ? ":white_check_mark:" : ":x:"
    label = decision.to_s == "approved" ? "Approved" : "Rejected"
    reviewer = admin_user&.email || "admin"
    text = "#{emoji} *#{label}* by #{reviewer}"
    text += "\n#{note}" if note.present?

    if proposal.slack_message_ts.present?
      post_thread(proposal.slack_message_ts, text: text)
    else
      post_message(text: "#{label}: #{proposal.display_name} (#{reviewer})")
    end
  end

  def self.curator_summary(result)
    return unless configured?

    published = Array(result["published"])
    queued = Array(result["queued_for_review"])
    rejected = Array(result["rejected"])

    lines = ["*Published:* #{published.size} · *Needs review:* #{queued.size} · *Rejected:* #{rejected.size}"]
    lines << "Auto-publish disabled (kill-switch on)." unless result["autopublish_enabled"]

    blocks = [
      header("Curator run"),
      section(lines.join("\n"))
    ]

    if queued.any?
      review_lines = queued.first(8).map { |item| "• <#{item['admin_url']}|#{item['name']}> — #{item['reason']}" }
      blocks << section("*Awaiting approval*\n#{review_lines.join("\n")}")
    end

    post_message(blocks: blocks, text: "Curator run: #{published.size} published, #{queued.size} awaiting review")
  end

  def self.header(text)
    { type: "header", text: { type: "plain_text", text: text.truncate(150), emoji: true } }
  end

  def self.section(text)
    { type: "section", text: { type: "mrkdwn", text: text } }
  end

  def self.context(text)
    { type: "context", elements: [{ type: "mrkdwn", text: text }] }
  end

  def self.actions(*elements)
    { type: "actions", elements: elements }
  end

  def self.button(text, url)
    { type: "button", text: { type: "plain_text", text: text, emoji: true }, url: url }
  end

  def self.configured?
    use_api? || WEBHOOK_URL.present?
  end

  def self.admin_proposal_url(proposal)
    host = ENV.fetch("APP_HOST", "localhost:3000")
    protocol = host.include?("localhost") ? "http" : "https"
    "#{protocol}://#{host}/admin/proposals/#{proposal.id}"
  end

  private

  def self.use_api?
    BOT_TOKEN.present? && CHANNEL_ID.present?
  end

  def self.api_post(payload)
    uri = URI.parse(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{BOT_TOKEN}"
    request.body = payload.to_json
    http.request(request)
  rescue => e
    Rails.logger.debug("[SlackNotifier] HTTP error: #{e.message}")
    nil
  end

  def self.webhook_post(text:)
    return unless WEBHOOK_URL.present?

    uri = URI.parse(WEBHOOK_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 5
    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/json"
    request.body = { text: text }.to_json
    http.request(request)
  rescue => e
    Rails.logger.debug("[SlackNotifier] Webhook error: #{e.message}")
  end

  def self.blocks_to_fallback(blocks)
    return "" unless blocks

    blocks.filter_map do |block|
      case block[:type]
      when "header" then block.dig(:text, :text)
      when "section" then block.dig(:text, :text) || block[:fields]&.map { |field| field[:text] }&.join(" | ")
      when "context" then block[:elements]&.map { |element| element[:text] }&.join(" ")
      end
    end.join("\n")
  end
end
