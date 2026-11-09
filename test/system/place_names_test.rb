require "application_system_test_case"

class PlaceNamesTest < ApplicationSystemTestCase
  test "title and pin update live when the place name arrives" do
    room = chatrooms(:cluj)
    using_session(:watcher) do
      visit chatroom_path(room)
      assert_selector "turbo-cable-stream-source[connected]", count: 2, visible: :all
    end
    room.update!(place_name: "Cluj-Napoca, <b>Romania</b>")
    using_session(:watcher) do
      assert_selector "turbo-frame#chatroom_panel h2", text: "Cluj-Napoca, <b>Romania</b>"
      assert_selector ".leaflet-marker-icon[title='Cluj-Napoca, <b>Romania</b>']"
      assert_selector ".leaflet-marker-icon", count: Chatroom.count
    end
  end
end
