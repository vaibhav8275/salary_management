Rails.application.routes.draw do
  # Swagger UI and raw OpenAPI JSON (rswag-ui + rswag-api).
  #
  # Guarded because the rswag gems live in the development/test group and are
  # not loaded in production. Naming `Rswag` unconditionally raised NameError at
  # boot, which took down the whole app rather than just this feature.
  # `defined?` only inspects the constant, so it returns false in production
  # instead of raising.
  if defined?(Rswag::Ui) && defined?(Rswag::Api)
    mount Rswag::Ui::Engine => "/api-docs"
    mount Rswag::Api::Engine => "/api-docs"
  end

  # External health check (kept from the Rails 8 default scaffold). Reachable
  # without a token on purpose: the check has no credentials to send, and it lives
  # in `Rails::HealthController`, which does not inherit from
  # `ApplicationController`.
  get "up" => "rails/health#show", as: :rails_health_check

  # Authentication (LLD §9.4). `skip: :all` declares the Devise mapping without
  # any of Devise's conventional routes — the mapping is what `current_user`,
  # `authenticate_user!` and Warden use, and generating routes is not wanted
  # here, because Devise's `devise_for` would also publish a sign-out endpoint
  # and logout is out of scope.
  #
  # The `path` and `path_names` still matter: devise-jwt reads them off the
  # mapping to work out which request it dispatches a token for, so the path
  # declared below is the one it matches `POST` against.
  devise_for :users, skip: :all, path: "api/v1/auth", path_names: { sign_in: "login" }

  # The only authentication endpoint this API has: credentials in, JWT out.
  # Declared inside `devise_scope` so the request carries the `:user` mapping —
  # the same scope the token is issued and read under. `devise_scope` is a
  # routing constraint rather than a path prefix, so this stays a single route
  # and no nested namespace is implied.
  devise_scope :user do
    post "api/v1/auth/login", to: "api/v1/sessions#create"
  end

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

      resources :salary_imports, only: %i[create index show], path: "salary-imports" do
        # Nested rather than a separate top-level resource: an error row has no
        # meaning without the import it belongs to, and neither does the file.
        get :errors, on: :member
        get :csv, on: :member
      end

      get "reports/average-salary-by-department", to: "reports#average_salary_by_department"
      get "reports/total-payroll-by-country", to: "reports#total_payroll_by_country"
      get "reports/employee-counts", to: "reports#employee_counts"
      get "reports/salary-distribution", to: "reports#salary_distribution"
      get "reports/salary-trends", to: "reports#salary_trends"
    end
  end
end
