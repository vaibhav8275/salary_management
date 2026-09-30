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
        salary = create_salary_params

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
        salary = update_salary_params

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

      # The change history of this employee's salary records,
      # grouped by the record the change belongs to.
      #
      # Grouping is the point of this response. A flat list of versions spanning
      # every record answers "what changed?" but not "what happened to *this*
      # record?", so the UI cannot show a record's own log without re-deriving
      # the grouping in the browser from an id the list has to carry anyway.
      # The UI reads it as one accordion per salary record, so the grouping
      # belongs in the contract.
      def audit
        employee = find_employee
        versions = PaperTrail::Version
          .where(item_type: "SalaryRecord", item_id: employee.salary_records.select(:id))
          .order(created_at: :desc, id: :desc)

        render_data(grouped_versions(versions))
      end

      private

      def find_employee
        Employee.find(params[:employee_id] || params[:id])
      end

      # Split from the update params on purpose. The effective date identifies a
      # period in the history, so it is set on create and never moved afterwards;
      # permitting it here would let a caller believe a date changed when it did
      # not.
      def create_salary_params
        params.permit(:base_salary, :bonus, :allowance, :effective_date)
      end

      def update_salary_params
        params.permit(:base_salary, :bonus, :allowance)
      end

      def provided_or(salary, key, current)
        return current unless salary.key?(key)

        parse_amount(salary[key])
      end

      def manual
        PaperTrail.request(whodunnit: HR_MANAGER, controller_info: { source: SOURCE_MANUAL }) { yield }
      end

      # One entry per salary record, in the order the records' latest change
      # arrived (newest first), each holding that record's own versions newest
      # first.
      #
      # Every record has at least its create version, so in practice every record
      # of the employee gets a group. `group_by` preserves the order of first
      # appearance, and the list is already ordered newest-first, so the group
      # whose most recent change is newest comes first.
      def grouped_versions(versions)
        versions
          .group_by(&:item_id)
          .map do |record_id, record_versions|
            {
              salary_record_id: record_id,
              versions: SalaryAuditBlueprint.render_as_hash(record_versions)
            }
          end
      end
    end
  end
end
