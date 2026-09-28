# Factories for the whole domain (LLD §12).
#
# Every attribute the LLD marks required gets a sensible default, so an example
# or scenario only states the attribute it actually cares about. Sequences keep
# the unique columns unique (`employees.email`, `departments.name`,
# `countries.name`); they are rewound before every example and scenario, which is
# safe because the rows are rolled back with it.
#
# The one thing a factory cannot do alone is share a reference row between
# records, which a named currency, country or department needs — see
# ReferenceData.
FactoryBot.define do
  factory :currency do
    sequence(:code) { |n| format("C%02d", n) }
    sequence(:name) { |n| "Test Currency #{n}" }
    symbol { "$" }
  end

  # Reference data (LLD §2.4). The name is unique, which is why a named
  # department is fetched through ReferenceData rather than created twice.
  factory :department do
    sequence(:name) { |n| "Department #{n}" }
  end

  # Reference data (LLD §2.3). The currency is the country's, never the
  # employee's, so this is where a multi-currency example states its currency.
  factory :country do
    sequence(:name) { |n| "Country #{n}" }
    currency { ReferenceData.currency("USD") }

    trait :eur do
      currency { ReferenceData.currency("EUR") }
    end

    trait :gbp do
      currency { ReferenceData.currency("GBP") }
    end
  end

  factory :employee do
    sequence(:first_name) { |n| "Firstname#{n}" }
    sequence(:last_name) { |n| "Lastname#{n}" }
    sequence(:email) { |n| "employee#{n}@example.com" }
    department { ReferenceData.department("Engineering") }
    country
    hire_date { Date.new(2020, 1, 1) }

    # BR-8 — an employee's salary is denominated in the currency of their
    # country, so these traits set the country rather than a currency on the
    # employee. USD is the documented default; the two below cover the
    # multi-currency reporting examples (LLD §11).
    trait :eur do
      country { create(:country, :eur) }
    end

    trait :gbp do
      country { create(:country, :gbp) }
    end
  end

  factory :salary_record do
    employee
    base_salary { 50_000 }
    bonus { 0 }
    allowance { 0 }
    effective_date { Date.new(2025, 1, 1) }
  end

  factory :salary_import do
    sequence(:filename) { |n| "salaries-#{n}.csv" }
    sequence(:s3_object_key) { |n| format("imports/%d/salaries.csv", n) }
    status { :pending }
    total_records { 0 }
    processed_records { 0 }
    failed_records { 0 }
    created_by { 42 }
    started_at { nil }

    trait :processing do
      status { :processing }
      total_records { 100 }
      processed_records { 40 }
    end

    trait :completed do
      status { :completed }
      processed_records { 10 }
      total_records { 10 }
    end

    trait :completed_with_errors do
      status { :completed_with_errors }
      total_records { 10 }
      processed_records { 9 }
      failed_records { 1 }
    end
  end

  # `salary_import_errors.employee_id` is nullable (LLD §8.3) so a row naming an
  # unknown employee can still be reported, but the model currently declares
  # `belongs_to :employee` as required. The factory therefore builds an employee
  # so `create` works; the example that documents the nullable behaviour asserts
  # the validation on an unsaved record instead, where `employee: nil` is free.
  factory :salary_import_error do
    salary_import
    row_number { 2 }
    error_message { "Invalid row" }
    raw_data { {} }
    employee
  end
end
