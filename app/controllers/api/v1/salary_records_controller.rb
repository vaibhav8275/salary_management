require "bigdecimal"
require "bigdecimal/util"

module Api
  module V1
    class SalaryRecordsController < ApplicationController
      HR_MANAGER = "HR Manager".freeze
      SOURCE_MANUAL = "manual".freeze

      def show
        employee = find_employee
        record = SalaryService.new.current_salary_record(employee)
        render_data(record.nil? ? nil : SalaryRecordBlueprint.render_as_hash(record))
      end

      def create
        employee = find_employee
        salary = salary_params

        base = parse_amount(salary[:base_salary])
        bonus = parse_amount(salary[:bonus]) || BigDecimal("0")
        allowance = parse_amount(salary[:allowance]) || BigDecimal("0")
        effective_date = parse_date(salary[:effective_date])

        return render_error if base.nil? || effective_date.nil?

        record = manual do
          SalaryService.new.create_salary_record(
            employee,
            base_salary: base,
            bonus: bonus,
            allowance: allowance,
            effective_date: effective_date
          )
        end

        if record.persisted?
          render_data(SalaryRecordBlueprint.render_as_hash(record), status: :created)
        else
          render_error
        end
      end

      def update
        employee = find_employee
        record = employee.salary_records.find(params[:salary_record_id])
        salary = salary_params

        base = provided_or(salary, :base_salary, record.base_salary)
        bonus = provided_or(salary, :bonus, record.bonus)
        allowance = provided_or(salary, :allowance, record.allowance)

        return render_error if base.nil? || bonus.nil? || allowance.nil?

        updated = manual do
          SalaryService.new.update_salary_record(record, base_salary: base, bonus: bonus, allowance: allowance)
        end

        if updated.persisted?
          render_data(SalaryRecordBlueprint.render_as_hash(updated))
        else
          render_error
        end
      end

      def history
        employee = find_employee
        records = employee.salary_records
                          .includes(employee: { country: :currency })
                          .order(effective_date: :desc)
        render_data(SalaryRecordBlueprint.render_as_hash(records))
      end

      def audit
        employee = find_employee
        versions = PaperTrail::Version
          .where(item_type: "SalaryRecord", item_id: employee.salary_records.select(:id))
          .order(created_at: :desc, id: :desc)

        render_data(SalaryAuditBlueprint.render_as_hash(versions))
      end

      def revert
        record = SalaryRecord.find(params[:id])
        version = record.versions.reorder(id: :desc).first
        SalaryService.new.revert_salary_change(version) if version

        render_data(SalaryRecordBlueprint.render_as_hash(record.reload))
      end

      private

      def find_employee
        Employee.find(params[:employee_id] || params[:id])
      end

      def salary_params
        params.permit(:base_salary, :bonus, :allowance, :effective_date)
      end

      def provided_or(salary, key, current)
        return current unless salary.key?(key)

        parse_amount(salary[key])
      end

      def manual
        PaperTrail.request(whodunnit: HR_MANAGER, controller_info: { source: SOURCE_MANUAL }) { yield }
      end
    end
  end
end
