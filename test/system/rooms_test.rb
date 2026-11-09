require "application_system_test_case"

class RoomsTest < ApplicationSystemTestCase
  test "clicking the map creates a room, drops a pin and opens it" do
    visit root_path
    assert_difference -> { Chatroom.count }, 1 do
      find("#map").click(x: -200, y: 100)
      assert_selector "turbo-frame#chatroom_panel h2", text: /Chatroom \d+/
    end
    assert_current_path chatroom_path(Chatroom.last)
    assert_selector ".leaflet-marker-icon", count: Chatroom.count
  end

  test "clicking a pin switches the panel and the URL" do
    visit chatroom_path(chatrooms(:cluj))
    assert_no_difference "Chatroom.count" do
      find(".leaflet-marker-icon[title='Rome, Italy']").click
      assert_selector "turbo-frame#chatroom_panel h2", text: "Rome, Italy"
    end
    assert_current_path chatroom_path(chatrooms(:rome))
  end

  test "back returns to the previous room" do
    visit chatroom_path(chatrooms(:cluj))
    # Going back before Turbo finishes the frame visit (turbo:load) lets the late visit
    # overwrite the restoration, so wait for it to settle first.
    page.execute_script("addEventListener('turbo:load', () => document.documentElement.setAttribute('data-visit-settled', ''))")
    find(".leaflet-marker-icon[title='Rome, Italy']").click
    assert_selector "turbo-frame#chatroom_panel h2", text: "Rome, Italy"
    assert_current_path chatroom_path(chatrooms(:rome))
    assert_selector "html[data-visit-settled]", visible: :all
    page.go_back
    assert_selector "turbo-frame#chatroom_panel h2", text: "Chatroom #{chatrooms(:cluj).id}"
    assert_selector ".leaflet-marker-icon", count: Chatroom.count
  end

  test "double-clicking the map creates exactly one room" do
    visit root_path
    assert_difference -> { Chatroom.count }, 1 do
      find("#map").double_click(x: -250, y: 150)
      assert_selector "turbo-frame#chatroom_panel h2", text: /Chatroom \d+/
      # Let a stray second POST land before assert_difference counts.
      sleep 0.5
    end
  end
end
