# Response-level assertions shared by every feature.
#
# "Successful" is asserted as any 2xx rather than a single code, because the LLD
# does not fix the response contract (LLD §10) and a create endpoint may
# reasonably answer 200 or 201. Everything else is asserted precisely.
Then("the response should be successful") do
  expect(api_status).to be_between(200, 299),
                      "expected a successful response, got #{api_status} with body:\n#{api_response_body}"
end

Then("the response status should be {int}") do |status|
  expect(api_status).to eq(status),
                        "expected status #{status}, got #{api_status} with body:\n#{api_response_body}"
end

Then("the response should include errors") do
  expect(api_json).to include("errors"),
                         "expected an errors key, got: #{api_response_body}"
  expect(api_errors).not_to be_empty
end

Then("the response should contain an import id") do
  expect(import_id_from_response).not_to be_nil,
                                    "expected an import id, got: #{api_response_body}"
end
