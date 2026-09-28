Rails.application.routes.draw do
  # Swagger UI and raw OpenAPI JSON (rswag-ui + rswag-api).
  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"

  # External health check (kept from the Rails 8 default scaffold).
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :employees, only: %i[index show] do
        member do
          get "salary", to: "salary_records#show"
          post "salary", to: "salary_records#create"
          get "salary/history", to: "salary_records#history"
          get "salary/audit", to: "salary_records#audit"
          patch "salary/:salary_record_id", to: "salary_records#update"
        end
      end

      resources :salary_records, only: [], path: "salary-records" do
        post :revert, on: :member
      end

      resources :salary_imports, only: %i[create index show], path: "salary-imports"

      get "reports/average-salary-by-department", to: "reports#average_salary_by_department"
      get "reports/total-payroll-by-country", to: "reports#total_payroll_by_country"
      get "reports/employee-counts", to: "reports#employee_counts"
      get "reports/salary-distribution", to: "reports#salary_distribution"
      get "reports/salary-trends", to: "reports#salary_trends"
    end
  end
end
