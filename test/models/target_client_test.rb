require "test_helper"

class TargetClientTest < ActiveSupport::TestCase
  test "canonical returns one record per canonical name when duplicates exist" do
    keeper = target_clients(:one)
    duplicate = TargetClient.create!(name: keeper.name, description: "Duplicate row")

    names = TargetClient.canonical.order(:name).pluck(:name)

    assert_equal names, names.uniq
    assert_includes TargetClient.canonical.pluck(:id), keeper.id
    refute_includes TargetClient.canonical.pluck(:id), duplicate.id
  ensure
    duplicate&.destroy
  end
end
