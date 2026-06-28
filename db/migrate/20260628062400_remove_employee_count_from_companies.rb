class RemoveEmployeeCountFromCompanies < ActiveRecord::Migration[8.0]
  def change
    remove_column :companies, :employee_count, :string if column_exists?(:companies, :employee_count)
  end
end
