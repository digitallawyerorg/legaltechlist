class LogosController < ApplicationController
  def show
    company_logo = CompanyLogo.find_by!(company_id: params[:id])

    expires_in 1.year, public: true
    fresh_when(etag: company_logo, last_modified: company_logo.updated_at, public: true)
    return if performed?

    send_data company_logo.data, type: company_logo.content_type, disposition: "inline"
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end
end
