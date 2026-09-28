class SalaryRecordBlueprint < Blueprinter::Base
  identifier :id

  fields :base_salary, :bonus, :allowance

  field :effective_date do |record|
    record.effective_date.iso8601
  end

  association :currency, blueprint: CurrencyBlueprint do |record|
    record.employee.country.currency
  end
end
