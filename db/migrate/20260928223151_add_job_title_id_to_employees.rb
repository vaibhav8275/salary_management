class AddJobTitleIdToEmployees < ActiveRecord::Migration[8.1]
  def change
    # Every employee has a job title (locked at the database as well as in the
    # model, like department and country), so No NULL rows can enter.
    add_reference :employees, :job_title, null: false, foreign_key: true, index: true
  end
end
