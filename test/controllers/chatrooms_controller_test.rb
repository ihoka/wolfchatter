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
end
