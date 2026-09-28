require "rails_helper"

# LLD §8.1 — the uploaded CSV is stored in S3 and referenced only by
# `salary_imports.s3_object_key`. The key itself is never exposed to the client,
# so the storage seam has to be the only way the file is reached.
#
# `S3StorageService` is the assumed name; it is described by string so the missing
# constant does not break suite loading. The examples also assert that the
# application builds its own `Aws::S3::Client`, which is what makes the fake in
# spec/support/s3_fake.rb possible.
RSpec.describe "S3StorageService", :s3, type: :service do
  let(:service) { S3StorageService.new }
  let(:bucket) { Rails.application.config.x.s3.fetch(:bucket) }

  describe "configuration" do
    it "reads the bucket from configuration" do
      expect(bucket).to be_present
    end

    # LLD §8.1 — nothing about the file is passed through the job, so the client
    # has to be built where the key is known.
    it "builds its own AWS client" do
      expect(Aws::S3::Client).to receive(:new)

      service.send(:client)
    end
  end

  describe "#upload" do
    it "stores the object under the returned key" do
      key = service.upload("imports/1/salaries.csv", "employee_id,effective_date\n1,2026-01-01\n")

      expect(key).to eq("imports/1/salaries.csv")
      expect(S3TestDouble.contents[key]).to include("employee_id")
    end

    it "keeps the file bytes intact" do
      body = csv_from_rows([ { "employee_id" => "1", "effective_date" => "2026-01-01" } ])

      key = service.upload("imports/2/salaries.csv", body)

      expect(S3TestDouble.contents[key]).to eq(body)
    end

    it "overwrites an existing key" do
      service.upload("imports/3/salaries.csv", "first\n")
      service.upload("imports/3/salaries.csv", "second\n")

      expect(S3TestDouble.contents["imports/3/salaries.csv"]).to eq("second\n")
    end
  end

  describe "#download" do
    it "returns the stored body" do
      key = service.upload("imports/4/salaries.csv", "a,b\n1,2\n")

      expect(service.download(key)).to eq("a,b\n1,2\n")
    end

    it "raises when the key does not exist" do
      expect { service.download("imports/missing/salaries.csv") }.to raise_error(StandardError)
    end
  end

  describe "#exists?" do
    it "is true for a stored key" do
      key = service.upload("imports/5/salaries.csv", "a\n")

      expect(service.exists?(key)).to be(true)
    end

    it "is false for an unknown key" do
      expect(service.exists?("imports/nope/salaries.csv")).to be(false)
    end
  end

  describe "#delete" do
    it "removes the object" do
      key = service.upload("imports/6/salaries.csv", "a\n")
      service.delete(key)

      expect(S3TestDouble.contents).not_to have_key(key)
    end
  end

  describe "failure handling" do
    it "surfaces a storage failure rather than reporting success" do
      allow(S3TestDouble.client).to receive(:put_object).and_raise(Seahorse::Client::NetworkingError.new(IOError.new("boom")))

      expect { service.upload("imports/7/salaries.csv", "a\n") }.to raise_error(StandardError)
    end
  end
end
