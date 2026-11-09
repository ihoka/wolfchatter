require "application_system_test_case"

class SmokeTest < ApplicationSystemTestCase
  test "home page renders" do
    visit root_path
    assert_selector "body"
  end
end
