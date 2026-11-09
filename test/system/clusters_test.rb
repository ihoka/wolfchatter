require "application_system_test_case"

class ClustersTest < ApplicationSystemTestCase
  setup { seed_dense_area }

  test "dense area shows a cluster with a count" do
    page.driver.browser.logs.get(:browser) # drain earlier entries
    visit root_path
    assert_selector ".leaflet-marker-icon.map-cluster", text: /\A\d+\z/
    assert_operator cluster_counts.sum, :>=, 400
    assert_no_js_errors
  end

  test "clicking a cluster zooms in and creates no room" do
    visit root_path
    assert_selector ".map-cluster"
    zoom = find("#map_container")["data-map-current-zoom"].to_i

    assert_no_difference -> { Chatroom.count } do
      mark_marker_set_stale
      click_central_cluster
      assert_selector "#map_container[data-map-current-zoom='#{zoom + 2}']"
      assert_marker_set_refreshed
      assert_text "Click on the map to start a chat"
    end
  end

  test "zooming in far enough shows pins" do
    visit root_path
    assert_selector ".map-cluster"
    8.times do
      break if has_no_selector?(".map-cluster", wait: 0)

      mark_marker_set_stale
      click_central_cluster
      assert_marker_set_refreshed
    end
    assert_no_selector ".map-cluster"
    assert_selector ".leaflet-marker-icon[title]"
  end

  test "opening another room releases the previous room's pin" do
    room_a = Chatroom.create!(latitude: 45.05, longitude: 10.05, place_name: "Room A")
    room_b = Chatroom.create!(latitude: 45.05, longitude: 10.02, place_name: "Room B")
    visit chatroom_path(room_a)
    assert_selector "turbo-frame#chatroom_panel h2", text: "Room A"
    assert_selector ".map-cluster"

    mark_marker_set_stale
    page.execute_script("document.getElementById('map').leafletMap.setZoom(11)")
    assert_marker_set_refreshed
    assert_no_selector ".map-cluster"

    find(".leaflet-marker-icon[title='Room B']").click
    assert_selector "turbo-frame#chatroom_panel h2", text: "Room B"
    assert_current_path chatroom_path(room_b)
    assert_selector ".leaflet-marker-icon[title='Room A']", count: 1
    assert_selector ".leaflet-marker-icon[title='Room B']", count: 1

    mark_marker_set_stale
    page.execute_script("document.getElementById('map').leafletMap.setZoom(5)")
    assert_marker_set_refreshed
    assert_selector ".map-cluster"
    assert_no_selector ".leaflet-marker-icon[title='Room A']"
    assert_selector ".leaflet-marker-icon[title='Room B']", count: 1
  end

  private

  # The panel covers the top-right corner of the map, so click the cluster nearest the
  # map's centre rather than whichever comes first in the DOM.
  def click_central_cluster
    page.execute_script(<<~JS)
      const box = document.getElementById("map").getBoundingClientRect()
      const cx = box.left + box.width / 2, cy = box.top + box.height / 2
      const distance = (el) => {
        const r = el.getBoundingClientRect()
        return Math.hypot(r.left + r.width / 2 - cx, r.top + r.height / 2 - cy)
      }
      const clusters = [...document.querySelectorAll(".map-cluster")]
      clusters.forEach((el) => el.removeAttribute("data-test-central"))
      clusters.sort((a, b) => distance(a) - distance(b))[0].setAttribute("data-test-central", "")
    JS
    find(".map-cluster[data-test-central]").click
  end
end
