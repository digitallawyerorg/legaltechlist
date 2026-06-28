class ErrorsController < ApplicationController
  ERROR_PAGES = {
    not_found: {
      status: :not_found,
      title: "Page not found",
      heading: "Page not found",
      code: "404",
      message: "We couldn't find the page you're looking for. It may have moved, or the address may be mistyped."
    },
    unprocessable_entity: {
      status: :unprocessable_entity,
      title: "Request rejected",
      heading: "Your request couldn't be processed",
      code: "422",
      message: "The change you requested was rejected — often because your session expired or the form was submitted twice. Go back, refresh the page, and try again."
    },
    forbidden: {
      status: :forbidden,
      title: "Access denied",
      heading: "Access denied",
      code: "403",
      message: "You don't have permission to view this page. If you believe this is a mistake, try signing in or return to the public index."
    },
    internal_server_error: {
      status: :internal_server_error,
      title: "Something went wrong",
      heading: "Something went wrong",
      code: "500",
      message: "We're sorry — an unexpected error occurred on our end. Please try again in a few minutes, or head back to browse the index."
    }
  }.freeze

  ERROR_PAGES.each_key do |action|
    define_method(action) do
      render_error(action)
    end
  end

  private

  def render_error(action)
    @error = ERROR_PAGES.fetch(action)

    respond_to do |format|
      format.html { render action.to_s, status: @error[:status], layout: "application" }
      format.all { head @error[:status] }
    end
  end
end
