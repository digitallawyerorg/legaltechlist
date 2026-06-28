require "test_helper"

class TagNormalizationServiceTest < ActiveSupport::TestCase
  test "ai_related_tag_ids include canonical and alias tags" do
    ai = tags(:one)
    ml = tags(:two)

    ids = TagNormalizationService.ai_related_tag_ids

    assert_includes ids, ai.id
    assert_includes ids, ml.id
  end
end
