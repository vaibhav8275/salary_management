module Api
  module V1
    class ReportsController < ApplicationController
      GROUPINGS = %w[department country].freeze

      def average_salary_by_department
        render_data(reports.average_salary_by_department(**report_filters))
      end

      def total_payroll_by_country
        render_data(reports.total_payroll_by_country(**report_filters))
      end

      def salary_distribution
        render_data(reports.salary_distribution(**report_filters))
      end

      def salary_trends
        render_data(reports.salary_trends(**report_filters))
      end

      def employee_counts
        unless GROUPINGS.include?(params[:group_by])
          return render_error(message: "group_by must be department or country")
        end

        filters = { department: params[:department], country: params[:country] }
        rows = if params[:group_by] == "department"
                 reports.employee_count_by_department(**filters)
        else
                 reports.employee_count_by_country(**filters)
        end

        render_data(rows)
      end

      private

      def reports
        @reports ||= ReportService.new
      end

      def report_filters
        {
          department: params[:department],
          country: params[:country],
          from: parse_date(params[:from]),
          to: parse_date(params[:to])
        }
      end
    end
  end
end
