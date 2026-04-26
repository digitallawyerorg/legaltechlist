require_relative '../services/import_csv_to_company_service'

ActiveAdmin.register Company do

# See permitted parameters documentation:
# https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters

  scope("In Moderation") { |scope| scope.where(visible: false) }
  scope("Missing URL") { |scope| scope.missing_main_url }
  scope("Weak Description") { |scope| scope.weak_description }
  scope("Duplicate Name Candidates") { |scope| scope.duplicate_name_candidates.order("LOWER(TRIM(companies.name)), companies.created_at DESC") }
  scope("Duplicate Domain Candidates") { |scope| scope.duplicate_domain_candidates.order("companies.canonical_domain, companies.main_url, companies.created_at DESC") }
  scope("Unknown Category") { |scope| scope.unknown_category }
  scope("Unknown Business Model") { |scope| scope.unknown_business_model }
  scope("Unknown Target Client") { |scope| scope.unknown_target_client }
  scope("Needs Review") { |scope| scope.needs_review }
  scope("Verified Quality") { |scope| scope.verified_quality }
  scope("Rejected Quality") { |scope| scope.rejected_quality }
  scope("Human Reviewed") { |scope| scope.human_reviewed }

  scope("Duplicates") do |scope|
    # Get names that appear more than once (accounting for spaces)
    duplicate_names = scope.pluck('companies.name')
                          .map(&:strip)
                          .group_by(&:itself)
                          .select { |_, v| v.length > 1 }
                          .keys

    # Return companies with those names
    scope.where("TRIM(companies.name) IN (?)", duplicate_names)
         .order("TRIM(companies.name), companies.visible DESC, companies.created_at DESC")
  end

  scope("Case-Insensitive Duplicates") do |scope|
    # Get names that appear more than once (case insensitive)
    duplicate_names = scope.pluck('LOWER(companies.name)')
                          .group_by(&:itself)
                          .select { |_, v| v.length > 1 }
                          .keys

    # Return companies with those names
    scope.where("LOWER(companies.name) IN (?)", duplicate_names)
         .order("LOWER(companies.name), companies.created_at DESC")
  end

  permit_params :name, :location, :founded_date, :category, :business_model, :target_client, :description, :main_url, :twitter_url, :angellist_url, :crunchbase_url, :linkedin_url, :facebook_url, :legalio_url, :status, :all_tags, :category_id, :sub_category_id, :business_model_id, :target_client_id, :latitude, :longitude, :contact_name, :contact_email, :visible, :codex_presenter, :employee_count, :codex_presentation_date, :logo_url, :total_funding_amount_usd, :funding_status, :number_of_funding_rounds, :exit_date, :quality_status, :verification_verdict, :quality_score, :verified_at, :enriched_at, :quality_reviewed_at, :human_reviewed_at, :fingerprint, :canonical_domain, :source, :source_url, tag_list: []

  batch_action :destroy, confirm: "Are you sure you want to delete these companies?" do |ids|
    Company.where(id: ids).destroy_all
    redirect_to collection_path, notice: "Successfully deleted #{ids.count} companies"
  end

  batch_action :make_visible, confirm: "Are you sure you want to make these companies visible?" do |ids|
    companies = Company.where(id: ids)
    count = companies.count
    companies.update_all(visible: true)
    redirect_to collection_path, notice: "Successfully made #{count} companies visible"
  end

  batch_action :count_invisible_duplicates, confirm: "Count invisible duplicate entries?", if: proc { true } do
    # First, get all names after trimming spaces
    duplicates = Company.pluck('companies.name')
                       .map(&:strip)
                       .group_by(&:itself)
                       .select { |_, v| v.length > 1 }
                       .keys

    # Then find companies with those names (using TRIM)
    invisible_duplicates = Company.where(visible: false)
                                .where("TRIM(companies.name) IN (?)", duplicates)
    count = invisible_duplicates.count

    redirect_to collection_path, notice: "Found #{count} invisible duplicate entries that could be deleted"
  end

  batch_action :remove_invisible_duplicates, confirm: "Are you sure you want to delete all invisible duplicate entries? This cannot be undone!", if: proc { true } do
    # First, get all names after trimming spaces
    duplicates = Company.pluck('companies.name')
                       .map(&:strip)
                       .group_by(&:itself)
                       .select { |_, v| v.length > 1 }
                       .keys

    # Then find and delete companies with those names (using TRIM)
    invisible_duplicates = Company.where(visible: false)
                                .where("TRIM(companies.name) IN (?)", duplicates)
    count = invisible_duplicates.count
    invisible_duplicates.destroy_all

    redirect_to collection_path, notice: "Successfully deleted #{count} invisible duplicate entries"
  end

  batch_action :remove_case_duplicates, confirm: "This will keep the newest entry for each duplicate set (based on created_at). Are you sure?", if: proc { true } do |ids|
    selected_companies = Company.where(id: ids)

    # Group by lowercase name
    grouped = selected_companies.group_by { |c| c.name.downcase }
    deleted_count = 0

    grouped.each do |lowercase_name, companies|
      if companies.size > 1
        # Sort by created_at descending and keep the newest one
        to_keep = companies.max_by(&:created_at)
        companies.each do |company|
          if company.id != to_keep.id
            company.destroy
            deleted_count += 1
          end
        end
      end
    end

    redirect_to collection_path, notice: "Successfully deleted #{deleted_count} case-insensitive duplicates"
  end

  filter :name
  filter :location
  filter :description
  filter :category
  filter :sub_category
  filter :founded_date, as: :numeric, filters: [:eq, :gt, :lt], label: 'Founded Year'
  filter :status, as: :select, collection: ['active', 'inactive', 'acquired']
  filter :visible
  filter :quality_status
  filter :verification_verdict
  filter :quality_score
  filter :verified_at
  filter :human_reviewed_at
  filter :canonical_domain
  filter :source
  filter :created_at
  filter :updated_at
  filter :tags

######

  action_item :only => :index do
    link_to 'Upload CSV', :action => 'upload_csv'
  end

  action_item :only => :index do
    link_to 'Download CSV', :action => 'export_csv'
  end

  collection_action :upload_csv do
    render "admin/csv/upload_csv"
  end

  collection_action :import_csv, :method => :post do
    stats = ImportCsvToCompanyService.import(params[:dump][:file])
    redirect_to :action => :index,
                :notice => "CSV imported successfully. Created: #{stats[:created]}, Updated: #{stats[:updated]}, Skipped: #{stats[:skipped]} companies."
  end

  collection_action :export_csv, :method => :get do
    encoding = Encoding::UTF_8.name
    csv = CSV.generate(encoding: encoding) do |csv|
      ImportCsvToCompanyService.export(csv)
    end

    send_data csv,
      type: "text/csv; charset=#{encoding}; header=present",
      disposition: "attachment; filename=companies.csv"
  end

  ######

  index do
    selectable_column
    if params[:scope] == "duplicates"
      column :name do |company|
        div style: "color: #{company.visible ? 'green' : 'red'}" do
          text_node company.name
          text_node " (#{company.visible ? 'visible' : 'invisible'})"
        end
      end
      column :founded_date
      column :created_at
      column :updated_at
      column :category
      column :description
      column :main_url
      column :all_tags
      column :visible
    else
      column :name
      column :founded_date
      column :category
      column :sub_category
      column :description
      column :main_url
      column :all_tags
      column :visible
      column :quality_status
      column :canonical_domain
      column :logo do |company|
        if company.logo_url.present?
          image_tag company.logo_url, style: "height: 30px; width: 30px; object-fit: contain"
        end
      end
    end
    actions
  end

  form do |f|
    f.inputs do
      f.input :contact_name
      f.input :contact_email
      f.input :name,          :required => true
      f.input :location,      :required => true
      f.input :founded_date,  :required => true
      f.input :founders
      f.input :visible,       as: :boolean
      f.input :category,      as: :select, collection: Category.all.order(:name), :required => true, :include_blank => false
      f.input :sub_category,      as: :select, collection: SubCategory.all.order(:name), :required => true, :include_blank => false
      f.input :target_client, as: :select, collection: TargetClient.all, :required => true, :include_blank => false
      f.input :business_model,as: :select, collection: BusinessModel.all, :required => true, :include_blank => false
      f.input :description,   :required => true
      f.input :main_url
      f.input :twitter_url
      f.input :angellist_url
      f.input :crunchbase_url
      f.input :linkedin_url
      f.input :facebook_url
      f.input :legalio_url
      f.input :status,        as: :select, collection: ['active', 'inactive', 'acquired']
      f.input :all_tags
      f.input :codex_presenter
      f.input :codex_presentation_date
      f.input :logo_url
      f.input :total_funding_amount_usd
      f.input :funding_status, as: :select, collection: ['Operating', 'Seed', 'Early Stage Venture', 'Late Stage Venture', 'Private Equity', 'M&A']
      f.input :number_of_funding_rounds
      f.input :exit_date
    end
    f.actions do
      f.action :submit
      f.action :cancel
    end
  end
end
