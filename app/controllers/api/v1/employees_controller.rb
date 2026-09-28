module Api
  module V1
    class EmployeesController < ApplicationController
      DEFAULT_PER_PAGE = 25

      def index
        scope = Employee.joins(:department, :country, :job_title)
                        .includes(:department, country: :currency, job_title: [])
                        .order(id: :asc)
        scope = apply_search(scope, params[:search])
        scope = scope.where(departments: { name: params[:department] }) if params[:department].present?
        scope = scope.where(countries: { name: params[:country] }) if params[:country].present?

        page = params[:page].to_i
        page = 1 if page < 1
        per_page = params[:per_page].to_i
        per_page = DEFAULT_PER_PAGE if per_page < 1

        total_count = scope.count
        employees = scope.limit(per_page).offset((page - 1) * per_page)

        render_data(
          EmployeeBlueprint.render_as_hash(employees),
          meta: {
            "current_page" => page,
            "per_page" => per_page,
            "total_count" => total_count,
            "total_pages" => (total_count.to_f / per_page).ceil
          }
        )
      end

      def show
        employee = Employee.includes(country: :currency, department: [], job_title: [])
                           .find(params[:id])
        render_data(EmployeeBlueprint.render_as_hash(employee, view: :detail))
      end

      private

      def apply_search(scope, term)
        return scope if term.blank?

        like = "%#{term}%"
        scope.where(
          "first_name ILIKE :like OR last_name ILIKE :like OR email ILIKE :like " \
          "OR CONCAT(first_name, ' ', last_name) ILIKE :like " \
          "OR CAST(employees.id AS text) = :exact",
          like: like,
          exact: term
        )
      end
    end
  end
end
