require "application_system_test_case"

class MapPageTest < ApplicationSystemTestCase
  test "visitor sees the empty state" do
    visit root_path
    assert_selector "#map"
    assert_text "Click on the map to start a chat"
  end

  test "existing rooms appear as pins without duplicates" do
    visit root_path
    assert_selector ".leaflet-marker-icon", count: Chatroom.count
  end

  test "opening a room by URL shows its pin once and its title" do
    visit chatroom_path(chatrooms(:rome))
    assert_selector "turbo-frame#chatroom_panel h2", text: "Rome, Italy"
    assert_selector ".leaflet-marker-icon", count: Chatroom.count
  end

  test "map shows OpenStreetMap attribution" do
    visit root_path
    assert_selector ".leaflet-control-attribution", text: "OpenStreetMap contributors"
  end

  test "page loads without Content Security Policy violations" do
    visit root_path
    assert_selector ".leaflet-marker-icon", count: Chatroom.count
    csp_errors = page.driver.browser.logs.get(:browser).select { _1.message.include?("Content Security Policy") }
    assert_empty csp_errors.map(&:message)
  end
end
