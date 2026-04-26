ActiveAdmin.register PipelineRun do
  actions :index, :show

  scope :all, default: true
  scope("Recent") { |scope| scope.recent }
  scope("Running") { |scope| scope.running }
  scope("Failed") { |scope| scope.failed }

  filter :name
  filter :run_type
  filter :status
  filter :agent_name
  filter :started_at
  filter :finished_at
  filter :created_at

  index do
    column :name
    column :run_type
    column :status
    column :agent_name
    column :records_processed
    column :started_at
    column :finished_at
    column :created_at
    actions
  end

  show do
    attributes_table do
      row :name
      row :run_type
      row :status
      row :agent_name
      row :records_processed
      row :started_at
      row :finished_at
      row :error_message
      row :details
      row :created_at
      row :updated_at
    end
  end
end
