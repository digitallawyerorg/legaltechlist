# frozen_string_literal: true

module TaxonomyFacetLookup
  extend ActiveSupport::Concern

  FACET_TYPES = %i[category business_model target_client tag].freeze

  included do
    before_action :assign_taxonomy_facet, only: :index
    before_action :redirect_legacy_facet_urls, only: :index
    before_action :redirect_single_category_query, only: :index
  end

  private

  def assign_taxonomy_facet
    @taxonomy_facet = resolve_taxonomy_facet
    @facet_category_ids = facet_category_ids
    @facet_business_model_ids = facet_business_model_ids
    @facet_target_client_ids = facet_target_client_ids
    @facet_tag_id = facet_tag_id
  end

  def resolve_taxonomy_facet
    if request.path.start_with?("/categories/") && params[:category].present?
      category = Category.find_by_slug_or_id(params[:category])
      raise ActiveRecord::RecordNotFound unless category

      { type: :category, record: category, label: category.name }
    elsif request.path.start_with?("/business_models/") && params[:business_model].present?
      business_model = BusinessModel.find_by_slug_or_id(params[:business_model])
      raise ActiveRecord::RecordNotFound unless business_model

      { type: :business_model, record: business_model, label: business_model.name }
    elsif request.path.start_with?("/target_clients/") && params[:target_client].present?
      target_client = TargetClient.find_by_slug_or_id(params[:target_client])
      raise ActiveRecord::RecordNotFound unless target_client

      { type: :target_client, record: target_client, label: target_client.name }
    elsif request.path.start_with?("/tags/") && params[:tag].present?
      tag = Tag.find_by_slug_or_id(params[:tag]) || Tag.find_by(name: CGI.unescape(params[:tag].to_s))
      raise ActiveRecord::RecordNotFound unless tag

      { type: :tag, record: tag, label: tag.name }
    end
  end

  def facet_category_ids
    return [] unless @taxonomy_facet&.dig(:type) == :category

    [@taxonomy_facet[:record].id]
  end

  def facet_business_model_ids
    return [] unless @taxonomy_facet&.dig(:type) == :business_model

    [@taxonomy_facet[:record].id]
  end

  def facet_target_client_ids
    return [] unless @taxonomy_facet&.dig(:type) == :target_client

    [@taxonomy_facet[:record].id]
  end

  def facet_tag_id
    return unless @taxonomy_facet&.dig(:type) == :tag

    @taxonomy_facet[:record].id
  end

  def redirect_legacy_facet_urls
    return if @taxonomy_facet.blank?

    record = @taxonomy_facet[:record]
    param_key = @taxonomy_facet[:type]
    raw_param = params[param_key].to_s
    decoded = CGI.unescape(raw_param)
    needs_redirect = raw_param.match?(/\A\d+\z/) || (record.slug.present? && decoded != record.slug)
    return unless needs_redirect
    return if record.slug.blank?

    redirect_target = public_send(:"#{param_key}_path", record, request.query_parameters.symbolize_keys.except(param_key))
    redirect_to redirect_target, status: :moved_permanently
  end

  def redirect_single_category_query
    return unless request.path == companies_path
    return if params[:query].present? || params[:country].present? || params[:city].present? || params[:location].present?
    return if selected_statuses.any?

    category_values = Array(params[:category]).map(&:presence).compact
    return unless category_values.size == 1

    category = Category.find_by_slug_or_id(category_values.first)
    return unless category&.slug.present?

    redirect_to category_path(category, request.query_parameters.symbolize_keys.except(:category)), status: :moved_permanently
  end
end
