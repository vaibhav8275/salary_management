require "json"

# JSON response helpers shared by RSpec request specs and Cucumber step
# definitions, so both suites read the API the same way.
#
# The envelope below is the *assumed* contract. LLD §10 states that "exact
# naming and response contracts are finalized during implementation", so the
# assumption is isolated in this one file: if the real response shape differs,
# only these accessors need to change.
#
#   200 collection → { "data": [...], "meta": { ...pagination... } }
#   200 member     → { "data": { ... } }
#   4xx/5xx        → { "errors": [ { ... } ] }
module ApiResponseHelpers
  # In RSpec request specs the response object is the ActionDispatch mock
  # response. Cucumber's World also exposes the Rack::Test API (post/get set
  # `last_response`), but its inherited `response` accessor is never populated,
  # so fall back to `last_response` when the response is nil.
  def api_response
    value = response
    return value unless value.nil?

    respond_to?(:last_response) ? last_response : nil
  end

  def api_response_body
    api_response.body
  end

  def api_status
    api_response.status
  end

  def api_json
    JSON.parse(api_response_body)
  rescue JSON::ParserError
    raise "Expected a JSON response but got status #{api_status} with body:\n#{api_response_body}"
  end

  def api_data
    envelope_key("data")
  end

  def api_meta
    envelope_key("meta")
  end

  def api_errors
    envelope_key("errors")
  end

  # Currency is always explicit (BR-8): monetary payloads are expected to name
  # the currency they are denominated in.
  def api_currency_code(payload = api_data)
    return nil if payload.nil?

    if payload.is_a?(Array)
      codes = payload.map { |item| api_currency_code(item) }.compact.uniq
      codes.size == 1 ? codes.first : codes
    elsif payload.key?("currency")
      currency = payload["currency"]
      currency.is_a?(Hash) ? currency["code"] : currency
    end
  end

  private

  def envelope_key(key)
    body = api_json

    unless body.is_a?(Hash) && body.key?(key)
      raise "Expected response JSON to contain a #{key.inspect} key, got: #{body.inspect}"
    end

    body[key]
  end
end
