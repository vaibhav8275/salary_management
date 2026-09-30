require "bigdecimal"
require "bigdecimal/util"

class ApplicationController < ActionController::API
  # Every API endpoint requires a valid bearer token.
  #
  # The filter is on the base controller rather than on each controller so a new
  # endpoint is authenticated by default and has to be *deliberately* opened with
  # `skip_before_action`. Adding a filter to every controller is how an open
  # endpoint appears: the one that gets forgotten.
  #
  # This is the whole of the access control. There is no authorization layer
  # because the system has a single HR persona — an authenticated caller is the
  # HR user and may reach every route below this filter. A failure throws
  # `:warden`, which `JsonFailureApp` renders as a 401 in the same error
  # envelope as everything else, so an unauthenticated request cannot fall
  # through to an action.
  before_action :authenticate_user!

  rescue_from ActiveRecord::RecordNotFound do |_exception|
    render json: { errors: [ { code: "not_found", message: "resource not found" } ] }, status: :not_found
  end

  protected

  def render_data(data, status: :ok, meta: nil)
    payload = { data: data }
    payload[:meta] = meta if meta.present?
    render json: payload, status: status
  end

  def render_error(status: :unprocessable_content, code: "validation_error", message: "invalid request")
    render json: { errors: [ { code: code, message: message } ] }, status: status
  end

  def parse_amount(value)
    return if value.nil? || value.to_s.blank?

    BigDecimal(value.to_s)
  rescue ArgumentError
    nil
  end

  def parse_date(value)
    return if value.nil? || value.to_s.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end
