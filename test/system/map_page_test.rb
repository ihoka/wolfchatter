require "application_system_test_case"

class MapPageTest < ApplicationSystemTestCase
  test "visitor sees the empty state" do
    visit root_path
    assert_selector "#map"
    assert_text "Click on the map to start a chat"
  end
end
