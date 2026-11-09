require "test_helper"

class ChatroomsControllerTest < ActionDispatch::IntegrationTest
  test "root shows the empty panel" do
    get root_path
    assert_response :success
    assert_select "title", "Wolfchatter"
    assert_select "#map"
    assert_select "#markers"
    assert_select "turbo-frame#chatroom_panel", text: /Click on the map to start a chat/
  end

  test "index renders a marker per room" do
    get root_path
    assert_select "#markers [data-controller=marker]", count: Chatroom.count
    assert_select "##{dom_id(chatrooms(:rome), :marker)}[data-marker-title-value=?]", "Rome, Italy"
  end

  test "create with valid coordinates redirects to the room" do
    assert_difference "Chatroom.count", 1 do
      post chatrooms_path, params: { chatroom: { latitude: 45.5, longitude: 10.25 } }
    end
    assert_redirected_to chatroom_path(Chatroom.last)
    assert_response :see_other
  end

  test "create rejects out-of-range coordinates" do
    assert_no_difference "Chatroom.count" do
      post chatrooms_path, params: { chatroom: { latitude: 10, longitude: 200 } }
    end
    assert_response :unprocessable_content
    assert_select "turbo-frame#chatroom_panel"
  end

  test "the 11th room created within a minute is rate limited" do
    10.times { post chatrooms_path, params: { chatroom: { latitude: 45.5, longitude: 10.25 } } }
    assert_no_difference "Chatroom.count" do
      post chatrooms_path, params: { chatroom: { latitude: 45.5, longitude: 10.25 } }
    end
    assert_response :too_many_requests
    assert_select "turbo-frame#chatroom_panel", text: /creating rooms too fast/
  end

  test "map starts centred on Europe at zoom 5" do
    get root_path
    assert_select "#map_container[data-map-zoom-value='5'][data-map-center-value='[48.0, 15.0]']"
  end

  test "show renders the full page with the room open" do
    get chatroom_path(chatrooms(:cluj))
    assert_response :success
    assert_select "#map"
    assert_select "turbo-frame#chatroom_panel h2##{dom_id(chatrooms(:cluj), :title)}", "Chatroom #{chatrooms(:cluj).id}"
  end

  test "show as a frame request renders only the panel" do
    get chatroom_path(chatrooms(:rome)), headers: { "Turbo-Frame" => "chatroom_panel" }
    assert_response :success
    assert_select "turbo-frame#chatroom_panel h2", "Rome, Italy"
    assert_select "#markers", count: 0
  end

  test "show for an unknown room is not found" do
    get chatroom_path(id: 999_999)
    assert_response :not_found
  end
end
