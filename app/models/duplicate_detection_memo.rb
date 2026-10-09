# Decoded duplicate-detection data, held for one unit of work — a request, a job, a test.
#
# Duplicate detection reads the same company-wide data many times per request, so the
# decoded copy is kept in memory rather than read back out of the shared cache each time.
# It is keyed by Company.duplicate_candidate_cache_version, but that version only sees
# updated_at and the row count, so writes that skip timestamps (update_columns,
# update_all) leave it unchanged. A copy that outlived its request would serve those rows
# stale for as long as the thread lived, so it lives in CurrentAttributes, which Rails
# clears whenever the executor finishes a unit of work and around every test.
class DuplicateDetectionMemo < ActiveSupport::CurrentAttributes
  attribute :identity_index, :candidate_ids
end
