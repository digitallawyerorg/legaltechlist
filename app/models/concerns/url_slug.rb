# frozen_string_literal: true

module UrlSlug
  extend ActiveSupport::Concern

  SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  included do
    before_validation :assign_slug_from_source, if: :should_assign_slug?
    validates :slug, presence: true, uniqueness: true, format: { with: SLUG_FORMAT }, if: -> { slug.present? }
  end

  class_methods do
    def slug_for_name(name)
      LegaltechAtlas.slug_for(name)
    end

    def find_by_slug_or_id(param, scope: all)
      param = param.to_s.strip
      return nil if param.blank?

      if param.match?(/\A\d+\z/)
        scope.find_by(id: param.to_i)
      else
        decoded = CGI.unescape(param)
        scope.find_by(slug: decoded) || scope.find_by(slug: param)
      end
    end

    def find_by_slug_or_id!(param, scope: all)
      find_by_slug_or_id(param, scope: scope) || raise(ActiveRecord::RecordNotFound)
    end

    def assign_unique_slugs!(scope: all, slug_source: :name, dry_run: true)
      reserved = Set.new(where.not(slug: [nil, ""]).pluck(:slug))
      updates = []

      scope.order(:id).find_each do |record|
        next if record.slug.present?

        base = slug_for_name(record.public_send(slug_source))
        base = "record-#{record.id}" if base.blank?
        candidate = base
        suffix = 2
        while reserved.include?(candidate)
          candidate = "#{base}-#{suffix}"
          suffix += 1
        end

        reserved << candidate
        updates << [record.id, candidate]
      end

      unless dry_run
        updates.each do |record_id, slug|
          where(id: record_id).update_all(slug: slug, updated_at: Time.current)
        end
      end

      updates
    end
  end

  def initialize_dup(other)
    super
    self.slug = nil
  end

  def slug_source_value
    public_send(slug_source_attribute)
  end

  def slug_source_attribute
    :name
  end

  def to_param
    slug.presence || id.to_s
  end

  private

  def should_assign_slug?
    slug.blank? && slug_source_value.present?
  end

  def assign_slug_from_source
    base = self.class.slug_for_name(slug_source_value)
    return if base.blank?

    candidate = base
    suffix = 2
    while self.class.where.not(id: id).exists?(slug: candidate)
      candidate = "#{base}-#{suffix}"
      suffix += 1
    end

    self.slug = candidate
  end
end
