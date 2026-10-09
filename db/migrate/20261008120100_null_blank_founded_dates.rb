class NullBlankFoundedDates < ActiveRecord::Migration[8.0]
  # An empty-string founding year reads as "present" to every `founded_date: nil`
  # count, so those records dropped out of the missing-year backlog (IP Author, #17266).
  def up
    execute "UPDATE companies SET founded_date = NULL WHERE btrim(founded_date) = ''"
  end

  def down; end
end
