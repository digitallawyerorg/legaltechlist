Rails.application.routes.draw do
  get 'up', to: proc { [200, { 'Content-Type' => 'text/plain' }, ['OK']] }, as: :rails_health_check
  get 'logos/:id', to: 'logos#show', as: :company_logo

  # Admin and Authentication
  devise_for :admin_users, path: "admin", path_names: { sign_in: "login", sign_out: "logout" }
  get 'admin', to: 'admin/app#show', as: :admin_root
  get 'admin/app', to: 'admin/app#show', as: :custom_admin_root
  get 'admin/quality', to: 'admin/quality#index', as: :custom_admin_quality
  get 'admin/review/companies', to: 'admin/company_reviews#index', as: :custom_admin_company_reviews
  post 'admin/review/companies/next-description-review', to: 'admin/company_reviews#create_next_description_review', as: :custom_admin_next_description_review
  post 'admin/review/companies/next-duplicate-domain-review', to: 'admin/company_reviews#create_next_duplicate_domain_review', as: :custom_admin_next_duplicate_domain_review
  get 'admin/review/companies/:id', to: 'admin/company_reviews#show', as: :custom_admin_company_review
  post 'admin/review/companies/:id/agent-review', to: 'admin/company_reviews#create_agent_review', as: :custom_admin_company_agent_review
  post 'admin/review/companies/:id/duplicate-review', to: 'admin/company_reviews#create_duplicate_review', as: :custom_admin_company_duplicate_review
  get 'admin/pipeline-runs', to: 'admin/pipeline_run_reviews#index', as: :custom_admin_pipeline_runs
  get 'admin/pipeline-runs/:id', to: 'admin/pipeline_run_reviews#show', as: :custom_admin_pipeline_run
  post 'admin/pipeline-runs/:id/company-proposals', to: 'admin/pipeline_run_reviews#queue_candidate_proposals', as: :custom_admin_pipeline_run_company_proposals
  get 'admin/proposals', to: 'admin/company_proposals#index', as: :custom_admin_company_proposals
  post 'admin/proposals/batch', to: 'admin/company_proposals#batch_update', as: :batch_custom_admin_company_proposals
  get 'admin/proposals/:id', to: 'admin/company_proposals#show', as: :custom_admin_company_proposal
  get 'admin/proposals/:id/edit', to: 'admin/company_proposals#edit', as: :edit_custom_admin_company_proposal
  patch 'admin/proposals/:id', to: 'admin/company_proposals#update'
  post 'admin/proposals/:id/enrich', to: 'admin/company_proposals#enrich', as: :enrich_custom_admin_company_proposal
  post 'admin/proposals/:id/approve', to: 'admin/company_proposals#approve', as: :approve_custom_admin_company_proposal
  post 'admin/proposals/:id/reject', to: 'admin/company_proposals#reject', as: :reject_custom_admin_company_proposal
  get 'admin/agent-reviews', to: 'admin/agent_reviews#index', as: :custom_admin_agent_reviews
  get 'admin/agent-reviews/:id', to: 'admin/agent_reviews#show', as: :custom_admin_agent_review
  post 'admin/agent-reviews/:id/apply', to: 'admin/agent_reviews#apply', as: :apply_custom_admin_agent_review
  post 'admin/agent-reviews/:id/reject', to: 'admin/agent_reviews#reject', as: :reject_custom_admin_agent_review
  post 'admin/agent-reviews/:id/follow-up', to: 'admin/agent_reviews#follow_up', as: :follow_up_custom_admin_agent_review
  get 'admin/app/resources/:resource', to: 'admin/resources#index', as: :custom_admin_resources
  get 'admin/app/resources/:resource/new', to: 'admin/resources#new', as: :new_custom_admin_resource
  post 'admin/app/resources/:resource', to: 'admin/resources#create'
  get 'admin/app/resources/:resource/:id/edit', to: 'admin/resources#edit', as: :edit_custom_admin_resource
  patch 'admin/app/resources/:resource/:id', to: 'admin/resources#update', as: :custom_admin_resource_record
  delete 'admin/app/resources/:resource/:id', to: 'admin/resources#destroy'
  get 'admin/app/companies', to: 'admin/company_management#index', as: :custom_admin_companies
  get 'admin/app/companies/new', to: 'admin/company_management#new', as: :new_custom_admin_company
  post 'admin/app/companies', to: 'admin/company_management#create'
  get 'admin/app/companies/upload', to: 'admin/company_management#upload', as: :upload_custom_admin_companies_csv
  post 'admin/app/companies/import', to: 'admin/company_management#import', as: :import_custom_admin_companies_csv
  post 'admin/app/companies/review-import-candidates', to: 'admin/company_management#review_import_candidates', as: :review_import_candidates_custom_admin_companies_csv
  get 'admin/app/companies/export', to: 'admin/company_management#export', as: :export_custom_admin_companies_csv
  get 'admin/app/companies/:id/edit', to: 'admin/company_management#edit', as: :edit_custom_admin_company
  patch 'admin/app/companies/:id', to: 'admin/company_management#update', as: :custom_admin_company
  delete 'admin/app/companies/:id', to: 'admin/company_management#destroy'

  # Resources
  resources :companies, except: [:destroy] do
    collection do
      get :search
    end
  end
  root to: 'static_pages#home'

  # Company filters
  get 'categories/:category' => 'companies#index', as: :category
  get 'business_models/:business_model' => 'companies#index', as: :business_model
  get 'target_clients/:target_client' => 'companies#index', as: :target_client

  # Company views
  get 'feed', to: 'companies#feed'
  get 'map', to: 'companies#map'

  # Static pages
  get 'about', to: 'static_pages#about'
  get 'about/data', to: redirect('/statistics/methodology', status: 301)
  get 'sitemap.xml', to: 'sitemap#index', defaults: { format: :xml }, as: :sitemap

  get 'statistics', to: 'static_pages#statistics'
  get 'statistics/methodology', to: 'static_pages#methodology', as: :statistics_methodology
  get 'statistics/tag_distribution', to: 'static_pages#tag_distribution'
  get 'statistics/tag_distribution/download', to: 'static_pages#download_tag_distribution', as: :download_tag_distribution
  get 'statistics/category_evolution', to: redirect('/statistics/category_evolution_5_years', status: 301)
  get 'statistics/category_evolution/download', to: redirect('/statistics/category_evolution_5_years/download', status: 301)

  # Total Companies routes with format support
  get 'statistics/total_companies', to: 'static_pages#total_companies', as: :statistics_total_companies
  get 'statistics/total_companies_all_time', to: 'static_pages#total_companies_all_time', as: :statistics_total_companies_all_time
  get 'statistics/companies_founded', to: 'static_pages#companies_founded', as: :statistics_companies_founded

  # New analytics pages
  get 'statistics/innovation_hubs', to: redirect('/statistics/country_distribution?view=region', status: 301)
  get 'statistics/exit_patterns', to: redirect('/statistics', status: 301)
  get 'statistics/exit_patterns/download', to: redirect('/statistics', status: 301)
  get 'statistics/founders_journey', to: redirect('/statistics', status: 301)
  get 'statistics/founders_journey/download', to: redirect('/statistics', status: 301)

  get 'static_pages/home'
  get 'admin/pieter', to: 'admin/pieter#index'

  # Add tag routes
  get 'tags/:tag', to: 'companies#index', as: :tag

  # Statistics routes
  get 'statistics/country_distribution', to: 'static_pages#country_distribution', as: :statistics_country_distribution
  get 'statistics/companies_by_region', to: 'static_pages#companies_by_region', as: :statistics_companies_by_region
  get 'statistics/funding_by_region', to: 'static_pages#funding_by_region', as: :statistics_funding_by_region
  get 'statistics/target_client', to: 'static_pages#target_client', as: :statistics_target_client
  get 'statistics/target_client/download', to: 'static_pages#download_target_client', as: :download_target_client
  get 'statistics/business_model', to: 'static_pages#business_model', as: :statistics_business_model
  get 'statistics/business_model/download', to: 'static_pages#download_business_model', as: :download_business_model
  get 'statistics/venture_stage', to: 'static_pages#venture_stage', as: :statistics_venture_stage
  get 'statistics/venture_stage/download', to: 'static_pages#download_venture_stage', as: :download_venture_stage
  get 'statistics/funding_stages', to: redirect('/statistics/venture_stage', status: 301)
  get 'statistics/funding_stages/download', to: redirect('/statistics/venture_stage/download', status: 301)
  get 'statistics/funding_efficiency', to: redirect('/statistics', status: 301)
  get 'statistics/funding_efficiency/download', to: redirect('/statistics', status: 301)
  get 'statistics/funding_concentration', to: redirect('/statistics', status: 301)
  get 'statistics/funding_concentration/download', to: redirect('/statistics', status: 301)
  get 'statistics/download_country_distribution', to: 'static_pages#download_country_distribution'
  get 'statistics/ai_trends', to: 'static_pages#ai_trends', as: :statistics_ai_trends
  get 'statistics/ai_trends/download', to: 'static_pages#download_ai_trends', as: :download_ai_trends
  get 'statistics/category_evolution_5_years', to: 'static_pages#category_evolution_5_years', as: :statistics_category_evolution_5_years
  get 'statistics/category_evolution_5_years/download', to: 'static_pages#download_category_evolution_5_years', as: :download_category_evolution_5_years
  get 'statistics/funding_by_category', to: 'static_pages#funding_by_category', as: :statistics_funding_by_category
  get 'statistics/funding_by_category/download', to: 'static_pages#download_funding_by_category', as: :download_funding_by_category
end
