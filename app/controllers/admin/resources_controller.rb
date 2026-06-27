module Admin
  class ResourcesController < BaseController
    RESOURCE_CONFIG = {
      "categories" => { model: Category, title: "Categories", fields: %i[name description] },
      "sub_categories" => { model: SubCategory, title: "Subcategories", fields: %i[name description category_id] },
      "business_models" => { model: BusinessModel, title: "Revenue Models", fields: %i[name description] },
      "target_clients" => { model: TargetClient, title: "Target Clients", fields: %i[name description] },
      "tags" => { model: Tag, title: "Tags", fields: %i[name] },
      "admin_users" => { model: AdminUser, title: "Admin Users", fields: %i[email password password_confirmation] }
    }.freeze

    before_action :set_resource_config
    before_action :set_record, only: %i[edit update destroy]

    def index
      @records = @model.order(:id).page(params[:page]).per(25)
    end

    def new
      @record = @model.new
    end

    def create
      @record = @model.new(record_params)

      if @record.save
        redirect_to custom_admin_resources_path(resource: @resource_key), notice: "#{@title.singularize} created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      attributes = record_params
      attributes = attributes.except(:password, :password_confirmation) if @model == AdminUser && attributes[:password].blank?

      if @record.update(attributes)
        redirect_to custom_admin_resources_path(resource: @resource_key), notice: "#{@title.singularize} updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @model == AdminUser && @record == current_admin_user
        redirect_to custom_admin_resources_path(resource: @resource_key), alert: "You cannot delete your own admin account."
      else
        @record.destroy
        redirect_to custom_admin_resources_path(resource: @resource_key), notice: "#{@title.singularize} deleted."
      end
    end

    private

    def set_resource_config
      @resource_key = params[:resource]
      @resource_config = RESOURCE_CONFIG.fetch(@resource_key) { raise ActiveRecord::RecordNotFound }
      @model = @resource_config[:model]
      @title = @resource_config[:title]
      @fields = @resource_config[:fields]
    end

    def set_record
      @record = @model.find(params[:id])
    end

    def record_params
      params.require(@model.model_name.param_key).permit(@fields)
    end
  end
end
