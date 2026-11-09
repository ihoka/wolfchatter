require "application_system_test_case"

class LiveUpdatesTest < ApplicationSystemTestCase
  test "another viewer sees new messages and pins live" do
    room = chatrooms(:rome)
    using_session(:watcher) do
      visit chatroom_path(room)
      assert_selector "turbo-cable-stream-source[connected]", count: 2, visible: :all
    end

    visit chatroom_path(room)
    fill_in placeholder: "write your user name here", with: "Ana"
    click_on "Save name"
    fill_in placeholder: "write message here", with: "<b>live</b>"
    click_on "Submit"
    within("##{dom_id(room, :messages)}") { assert_text "<b>live</b>" }
    assert_selector "##{dom_id(Message.last)}", count: 1
    find("#map").click(x: -300, y: 200)
    assert_selector ".leaflet-marker-icon", count: Chatroom.count

    using_session(:watcher) do
      within("##{dom_id(room, :messages)}") do
        assert_text "<b>live</b>"
        assert_no_selector "b", text: "live"
      end
      assert_selector ".leaflet-marker-icon", count: Chatroom.count
    end
  end

  test "going back to a room shows messages that arrived while away" do
    cluj = chatrooms(:cluj)
    visit chatroom_path(cluj)
    # Turbo finishes a frame "advance" visit (turbo:load) after the frame has rendered; going
    # back before that lets the late visit overwrite the restoration. Wait for it to settle.
    page.execute_script("addEventListener('turbo:load', () => document.documentElement.setAttribute('data-visit-settled', ''))")
    find(".leaflet-marker-icon[title='Rome, Italy']").click
    assert_selector "turbo-frame#chatroom_panel h2", text: "Rome, Italy"
    assert_current_path chatroom_path(chatrooms(:rome))
    assert_selector "html[data-visit-settled]", visible: :all
    cluj.messages.create!(author_name: "Bo", body: "while you were away")
    page.go_back
    within("##{dom_id(cluj, :messages)}") { assert_text "while you were away" }
  end

  test "off-screen new room does not appear in pins mode" do
    visit root_path
    assert_selector "turbo-cable-stream-source[connected]", visible: :all
    assert_selector ".leaflet-marker-icon", count: 2
    bounds = map_script("map.getBounds()")
    lat = (bounds["_southWest"]["lat"] + bounds["_northEast"]["lat"]) / 2
    outside = Chatroom.create!(latitude: lat, longitude: bounds["_southWest"]["lng"] - 10)
    assert_selector "##{dom_id(outside, :live_marker)}", visible: :all
    assert_selector ".leaflet-marker-icon", count: 2

    center = map_script("map.getCenter()")
    Chatroom.create!(latitude: center["lat"], longitude: center["lng"])
    assert_selector ".leaflet-marker-icon", count: 3
  end

  test "new room raises a cluster count live" do
    seed_dense_area
    visit root_path
    assert_selector "turbo-cable-stream-source[connected]", visible: :all
    size = MapMarkers.cell_size_for(5)
    lat, lng = 45.05, 10.05
    cell_lat = (lat / size).floor * size
    cell_lng = (lng / size).floor * size
    count = Chatroom.where(latitude: cell_lat...(cell_lat + size), longitude: cell_lng...(cell_lng + size)).count
    assert_selector ".map-cluster", exact_text: count.to_s
    assert_no_selector ".map-cluster", exact_text: (count + 1).to_s

    Chatroom.create!(latitude: lat, longitude: lng)
    assert_selector ".map-cluster", exact_text: (count + 1).to_s
    assert_no_selector ".map-cluster", exact_text: count.to_s
  end

  test "room created during a fetch survives the swap" do
    visit root_path
    assert_selector "turbo-cable-stream-source[connected]", visible: :all
    assert_selector ".leaflet-marker-icon", count: 2
    # Hold the next markers reply in the browser (after the server has answered, so the reply
    # cannot contain the new room) until the test releases it.
    page.execute_script(<<~JS)
      const realFetch = window.fetch
      window.fetch = async (...args) => {
        const response = await realFetch(...args)
        if (!String(args[0]).includes("/chatrooms/markers")) return response
        window.fetch = realFetch
        document.documentElement.dataset.markersHeld = ""
        await new Promise((resolve) => { window.releaseMarkers = resolve })
        return response
      }
    JS
    mark_marker_set_stale
    page.execute_script("document.getElementById('map').leafletMap.panBy([60, 40])")
    assert_selector "html[data-markers-held]", visible: :all

    center = map_script("map.getCenter()")
    room = Chatroom.create!(latitude: center["lat"], longitude: center["lng"])
    assert_selector ".leaflet-marker-icon[title='#{room.title}']"
    page.execute_script("window.releaseMarkers()")
    assert_marker_set_refreshed
    assert_selector ".leaflet-marker-icon[title='#{room.title}']"
    assert_selector ".leaflet-marker-icon", count: 3
  end
end
