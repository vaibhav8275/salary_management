# The step definitions call the API with the RSpec convention
# `post path, params: { ... }`. Under Rack::Test (which is what Cucumber's World
# routes requests through) the trailing keyword hash is passed to
# `Session#post(uri, params, env)` positionally, so the body would be encoded as
# `params[field]=value` and never reach the controller's `params`.
#
# These wrappers unwrap that single `params:` key so both test runners share the
# same request convention. A positional body (`post path, { field: value }`) is
# left untouched.
module CucumberRackTestParams
  %i[get post patch put delete options head].each do |verb|
    define_method(verb) do |uri, params = nil, env = {}, &block|
      if params.is_a?(Hash) && params.keys == [ :params ]
        super(uri, params[:params], env, &block)
      else
        super(uri, params, env, &block)
      end
    end
  end
end

World(CucumberRackTestParams)
