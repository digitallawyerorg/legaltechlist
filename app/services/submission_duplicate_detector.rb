class SubmissionDuplicateDetector
  WINDOW = 1.hour

  def self.duplicate?(fingerprint:)
    new(fingerprint: fingerprint).duplicate?
  end

  def self.record!(fingerprint:)
    new(fingerprint: fingerprint).record!
  end

  def initialize(fingerprint:)
    @fingerprint = fingerprint.to_s.strip
  end

  def duplicate?
    return false if fingerprint.blank?

    Rails.cache.read(cache_key).present?
  end

  def record!
    return if fingerprint.blank?

    Rails.cache.write(cache_key, true, expires_in: WINDOW)
  end

  private

  attr_reader :fingerprint

  def cache_key
    "submission_dup:#{Digest::SHA256.hexdigest(fingerprint)}"
  end
end
