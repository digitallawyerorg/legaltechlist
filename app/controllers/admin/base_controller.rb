module Admin
  class BaseController < ApplicationController
    before_action :authenticate_admin_user!

    layout "admin"

    # A reviewer whose session or CSRF token has aged out was being handed the public
    # 422 page — the generic "your session expired or the form was submitted twice",
    # rendered in the public site's chrome, with no way back into the queue and no
    # indication of which of those two things actually happened. The action is refused
    # either way; what changes here is that the refusal is legible and lands the
    # reviewer back where they were working.
    rescue_from ActionController::InvalidAuthenticityToken do |_exception|
      redirect_to(safe_referrer || custom_admin_companies_path,
                  alert: "That action was not carried out: your admin session had expired by the time the form was submitted. " \
                         "Nothing was changed. Sign in again if prompted, reload this page and repeat the action.")
    end

    private

    # Only ever back to a page inside this admin. The referrer is attacker-supplied, so
    # it is used as a same-origin admin path or not at all.
    def safe_referrer
      referrer = request.referer.presence
      return nil unless referrer

      uri = URI.parse(referrer)
      return nil unless uri.host.nil? || uri.host == request.host
      return nil unless uri.path.to_s.start_with?("/admin")

      uri.path
    rescue URI::InvalidURIError
      nil
    end
  end
end
