class EmployeeBlueprint < Blueprinter::Base
  identifier :id

  field :name do |employee|
    "#{employee.first_name} #{employee.last_name}"
  end

  fields :first_name, :last_name, :email

  field :department do |employee|
    employee.department.name
  end

  field :job_title do |employee|
    employee.job_title.title
  end

  field :country do |employee|
    employee.country.name
  end

  field :hire_date do |employee|
    employee.hire_date.iso8601
  end

  view :detail do
    association :currency, blueprint: CurrencyBlueprint do |employee|
      employee.country.currency
    end
  end
end
