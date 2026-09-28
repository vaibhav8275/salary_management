require "bigdecimal"
require "bigdecimal/util"

class ApplicationController < ActionController::API
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
