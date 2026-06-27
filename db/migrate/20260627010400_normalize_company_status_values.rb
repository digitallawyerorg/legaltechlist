class NormalizeCompanyStatusValues < ActiveRecord::Migration[7.0]
  def up
    execute <<~SQL.squish
      UPDATE companies
      SET status = LOWER(TRIM(status))
      WHERE status IS NOT NULL
        AND status <> LOWER(TRIM(status))
    SQL
  end

  def down
    # Status values are intentionally canonicalized to lower-case strings.
  end
end
