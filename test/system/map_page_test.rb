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

  test "page loads without Content Security Policy violations and keeps its nonce across Turbo visits" do
    page.driver.browser.logs.get(:browser) # drain earlier entries
    pins = Chatroom.count
    visit root_path
    assert_selector ".leaflet-marker-icon", count: pins
    nonce = find("meta[name=csp-nonce]", visible: false)[:content]
    assert_not_empty nonce

    page.execute_script("Turbo.visit(#{chatroom_path(chatrooms(:rome)).to_json})")
    assert_selector "turbo-frame#chatroom_panel h2", text: "Rome, Italy"
    assert_selector ".leaflet-marker-icon", count: pins
    assert_equal nonce, find("meta[name=csp-nonce]", visible: false)[:content]

    visit chatroom_path(chatrooms(:rome))
    assert_selector ".leaflet-marker-icon", count: pins
    csp_errors = page.driver.browser.logs.get(:browser).select { _1.message.include?("Content Security Policy") }
    assert_empty csp_errors.map(&:message)
  end

  test "tooltips show room titles as text, not HTML" do
    room = Chatroom.create!(latitude: 47, longitude: 15, place_name: "<b>bold</b>")
    visit root_path
    assert_selector ".leaflet-marker-icon[title='<b>bold</b>']"
    find(".leaflet-marker-icon[title='<b>bold</b>']").hover
    assert_selector ".leaflet-tooltip", text: "<b>bold</b>"
    assert_no_selector ".leaflet-tooltip b"
  end

  test "pan and zoom survive a full Turbo visit" do
    visit chatroom_path(chatrooms(:cluj))
    assert_selector ".leaflet-marker-icon", count: Chatroom.count
    find(".leaflet-control-zoom-in").click
    assert_selector "#map_container[data-map-current-zoom='6']"
    page.execute_script("Turbo.visit('#{chatroom_path(chatrooms(:rome))}')")
    assert_selector "turbo-frame#chatroom_panel h2", text: "Rome, Italy"
    assert_selector ".leaflet-marker-icon", count: Chatroom.count
    assert_equal 6, page.evaluate_script("document.getElementById('map').leafletMap.getZoom()")
  end

  test "deep link centres on its room" do
    rome = chatrooms(:rome)
    visit chatroom_path(rome)
    assert_selector "turbo-frame#chatroom_panel h2", text: "Rome, Italy"
    center = page.evaluate_script("document.getElementById('map').leafletMap.getCenter()")
    assert_in_delta rome.latitude, center["lat"], 0.01
    assert_in_delta rome.longitude, center["lng"], 0.01
  end
end
