require "aws-sdk-s3"
require "stringio"

# In-memory stand-in for the import bucket (LLD §8.1, ARCHITECTURE §4.5).
#
# Tests never talk to AWS. `Aws::S3::Client.new` is stubbed to return this
# object, so a scenario still exercises the genuine upload-then-read path —
# the API writes the object, the worker reads it back by key — without any
# network dependency or recorded VCR cassette.
class FakeS3Client
  def initialize(bucket: "salary-management-imports")
    @bucket = bucket
    @objects = {}
    @content_types = {}
  end

  attr_reader :bucket, :objects

  def put_object(bucket: nil, key:, body:, content_type: nil, **_options)
    @content_types[key] = content_type
    @objects[key] = body.respond_to?(:read) ? body.read : body.to_s
    true
  end

  def get_object(bucket: nil, key:, **_options)
    raise Aws::S3::Errors::NoSuchKey.new(nil, "NoSuchKey: #{key}") unless @objects.key?(key)

    StringIO.new(@objects[key])
  end

  def delete_object(bucket: nil, key:, **_options)
    @content_types.delete(key)
    @objects.delete(key)
    true
  end

  def object_exists?(bucket: nil, key:, **_options)
    @objects.key?(key)
  end

  def reset!
    @objects.clear
    @content_types.clear
  end
end

# Gives RSpec examples and Cucumber scenarios one shared fake bucket per
# example, and stubs the SDK entry point the application is expected to use.
module S3TestDouble
  class << self
    def client
      @client ||= FakeS3Client.new
    end

    def reset!
      @client = FakeS3Client.new
    end

    # Live view of the bucket: keys are object keys and values are the stored
    # body strings, so tests can stage a CSV (contents[key] = csv) and read it
    # back through the same read path as an API upload.
    def contents
      client.objects
    end
  end

  def fake_s3_bucket
    S3TestDouble.client
  end

  def stub_s3_storage!
    allow(Aws::S3::Client).to receive(:new) { S3TestDouble.client }
  end
end
