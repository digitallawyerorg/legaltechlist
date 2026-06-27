class ApplicationController < ActionController::Base
  include CacheKeyVersions

  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  before_action :block_deep_public_pagination
  before_action :detect_device_variant

  private

  def block_deep_public_pagination
    return unless request.get?
    return unless public_listing_path?

    page = params[:page].to_i
    return if page <= 20

    Rails.logger.debug("Blocked deep public pagination request path=#{request.fullpath} page=#{page}")
    head :too_many_requests
  end

  def public_listing_path?
    request.path == "/companies" ||
      request.path.start_with?("/tags/") ||
      request.path.start_with?("/categories/")
  end

  def detect_device_variant
    request.variant = :tablet if browser.device.tablet?
    request.variant = :desktop if !browser.device.mobile? && !browser.device.tablet?
  end
end
