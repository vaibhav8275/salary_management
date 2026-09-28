require "aws-sdk-s3"

class S3StorageService
  def initialize(bucket: Rails.application.config.x.s3.fetch(:bucket))
    @bucket = bucket
  end

  attr_reader :bucket

  def upload(key, body, content_type: "text/csv")
    client.put_object(bucket: @bucket, key: key, body: body, content_type: content_type)
    key
  end

  def download(key)
    response = client.get_object(bucket: @bucket, key: key)
    body = response.respond_to?(:body) ? response.body : response

    body.respond_to?(:read) ? body.read : body.to_s
  end

  def exists?(key)
    client.object_exists?(bucket: @bucket, key: key)
  end

  def delete(key)
    client.delete_object(bucket: @bucket, key: key)
  end

  private

  def client
    @client ||= begin
      config = Rails.application.config.x.s3
      Aws::S3::Client.new(
        region: config.fetch(:region),
        force_path_style: config.fetch(:force_path_style, false)
      )
    end
  end
end
