Rails.application.routes.draw do
  # Admin and Authentication
  devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)

  # Resources
  resources :companies
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
  get 'statistics', to: 'static_pages#statistics'
  get 'statistics/tag_distribution', to: 'static_pages#tag_distribution'
  get 'statistics/tag_distribution/download', to: 'static_pages#download_tag_distribution', as: :download_tag_distribution
  get 'statistics/category_evolution', to: 'static_pages#category_evolution'
  get 'statistics/category_evolution/download', to: 'static_pages#download_category_evolution', as: :download_category_evolution
  get 'statistics/total_companies', to: 'static_pages#total_companies'
  get 'statistics/total_companies/download', to: 'static_pages#download_total_companies', as: :download_total_companies
  get 'statistics/funding_concentration', to: 'static_pages#funding_concentration'
  get 'statistics/funding_concentration/download', to: 'static_pages#download_funding_concentration', as: :download_funding_concentration
  get 'statistics/growth_stage', to: 'static_pages#growth_stage'
  get 'statistics/growth_stage/download', to: 'static_pages#download_growth_stage', as: :download_growth_stage
  get 'statistics/target_client', to: 'static_pages#target_client'
  get 'statistics/target_client/download', to: 'static_pages#download_target_client', as: :download_target_client
  get 'statistics/country_distribution', to: 'static_pages#country_distribution'
  get 'statistics/country_distribution/download', to: 'static_pages#download_country_distribution', as: :download_country_distribution
  get 'statistics/funding_stages', to: 'static_pages#funding_stages'
  get 'statistics/funding_stages/download', to: 'static_pages#download_funding_stages', as: :download_funding_stages
  get 'statistics/funding_efficiency', to: 'static_pages#funding_efficiency'
  get 'statistics/funding_efficiency/download', to: 'static_pages#download_funding_efficiency', as: :download_funding_efficiency

  # New analytics pages
  get 'statistics/innovation_hubs', to: 'static_pages#innovation_hubs'
  get 'statistics/innovation_hubs/download', to: 'static_pages#download_innovation_hubs', as: :download_innovation_hubs
  get 'statistics/exit_patterns', to: 'static_pages#exit_patterns'
  get 'statistics/exit_patterns/download', to: 'static_pages#download_exit_patterns', as: :download_exit_patterns
  get 'statistics/founders_journey', to: 'static_pages#founders_journey'
  get 'statistics/founders_journey/download', to: 'static_pages#download_founders_journey', as: :download_founders_journey

  get 'static_pages/home'
  get 'admin/pieter', to: 'admin/pieter#index'

  # Add tag routes
  get 'tags/:tag', to: 'companies#index', as: :tag
end
