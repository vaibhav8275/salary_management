# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_01_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "countries", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "currency_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["currency_id"], name: "index_countries_on_currency_id"
    t.index ["name"], name: "index_countries_on_name", unique: true
  end

  create_table "currencies", force: :cascade do |t|
    t.string "code", limit: 3, null: false
    t.string "name", null: false
    t.string "symbol", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_currencies_on_code", unique: true
  end

  create_table "departments", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_departments_on_name", unique: true
  end

  create_table "employees", force: :cascade do |t|
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "email", null: false
    t.bigint "department_id", null: false
    t.bigint "country_id", null: false
    t.date "hire_date", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "job_title_id", null: false
    t.index ["country_id"], name: "index_employees_on_country_id"
    t.index ["department_id"], name: "index_employees_on_department_id"
    t.index ["email"], name: "index_employees_on_email", unique: true
    t.index ["first_name"], name: "index_employees_on_first_name"
    t.index ["job_title_id"], name: "index_employees_on_job_title_id"
    t.index ["last_name"], name: "index_employees_on_last_name"
  end

  create_table "job_titles", force: :cascade do |t|
    t.string "title", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["title"], name: "index_job_titles_on_title"
  end

  create_table "salary_import_errors", force: :cascade do |t|
    t.bigint "salary_import_id", null: false
    t.integer "row_number", null: false
    t.bigint "employee_id"
    t.text "error_message", null: false
    t.jsonb "raw_data", null: false
    t.datetime "created_at", null: false
    t.index ["employee_id"], name: "index_salary_import_errors_on_employee_id"
    t.index ["salary_import_id"], name: "index_salary_import_errors_on_salary_import_id"
  end

  create_table "salary_imports", force: :cascade do |t|
    t.string "filename", null: false
    t.integer "status", default: 0, null: false
    t.integer "total_records", null: false
    t.integer "processed_records", null: false
    t.integer "failed_records", null: false
    t.bigint "created_by", null: false
    t.datetime "started_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "salary_records", force: :cascade do |t|
    t.bigint "employee_id", null: false
    t.decimal "base_salary", precision: 15, scale: 2, null: false
    t.decimal "bonus", precision: 15, scale: 2, null: false
    t.decimal "allowance", precision: 15, scale: 2, null: false
    t.date "effective_date", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["effective_date"], name: "index_salary_records_on_effective_date"
    t.index ["employee_id", "effective_date"], name: "index_salary_records_on_employee_id_and_effective_date", unique: true
    t.index ["employee_id"], name: "index_salary_records_on_employee_id"
    t.check_constraint "allowance >= 0::numeric", name: "salary_records_allowance_non_negative"
    t.check_constraint "base_salary >= 0::numeric", name: "salary_records_base_salary_non_negative"
    t.check_constraint "bonus >= 0::numeric", name: "salary_records_bonus_non_negative"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.string "whodunnit"
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.string "event", null: false
    t.jsonb "object"
    t.jsonb "object_changes"
    t.string "source", default: "manual", null: false
    t.bigint "salary_import_id"
    t.datetime "created_at"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
    t.index ["salary_import_id"], name: "index_versions_on_salary_import_id"
    t.check_constraint "source::text = ANY (ARRAY['manual'::character varying, 'bulk_import'::character varying]::text[])", name: "versions_source_check"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "countries", "currencies"
  add_foreign_key "employees", "countries"
  add_foreign_key "employees", "departments"
  add_foreign_key "employees", "job_titles"
  add_foreign_key "salary_import_errors", "employees"
  add_foreign_key "salary_import_errors", "salary_imports"
  add_foreign_key "salary_imports", "users", column: "created_by"
  add_foreign_key "salary_records", "employees"
  add_foreign_key "versions", "salary_imports", on_delete: :nullify
end
