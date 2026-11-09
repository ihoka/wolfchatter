require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @room = chatrooms(:cluj)
    patch display_name_path, params: { display_name: { name: "Ana" }, chatroom_id: @room.id }, as: :turbo_stream
  end

  test "posting appends the message as the cookie's author" do
    assert_difference -> { @room.messages.count }, 1 do
      post chatroom_messages_path(@room), params: { message: { body: "Hello", author_name: "Mallory" } },
                                          as: :turbo_stream
    end
    assert_response :success
    assert_equal "Ana", @room.messages.last.author_name
    assert_select "turbo-stream[action=append][target=?]", dom_id(@room, :messages)
  end

  test "blank body is rejected" do
    assert_no_difference -> { Message.count } do
      post chatroom_messages_path(@room), params: { message: { body: "  " } }, as: :turbo_stream
    end
    assert_response :unprocessable_content
  end

  test "posting without a name is rejected" do
    delete display_name_path, params: { chatroom_id: @room.id }, as: :turbo_stream
    assert_no_difference -> { Message.count } do
      post chatroom_messages_path(@room), params: { message: { body: "hi" } }, as: :turbo_stream
    end
    assert_response :unprocessable_content
    assert_select "turbo-stream[action=replace][target=?]", dom_id(@room, :compose)
    assert_select "input[placeholder='write your user name here']"
  end

  test "message markup is escaped" do
    post chatroom_messages_path(@room), params: { message: { body: "<script>x</script>" } }, as: :turbo_stream
    assert_not_includes response.body, "<script>x</script>"
  end

  test "room page lists recent messages oldest first" do
    get chatroom_path(@room)
    bodies = css_select("##{dom_id(@room, :messages)} article").map { _1.at_css("p")&.text.to_s.strip }
    assert_equal [ messages(:hello).body, messages(:reply).body ], bodies
  end

  test "each message has a stable dom id" do
    get chatroom_path(@room)
    assert_select "article##{dom_id(messages(:hello))}"
  end

  test "non turbo stream requests get 406" do
    post chatroom_messages_path(@room), params: { message: { body: "hi" } }
    assert_response :not_acceptable
  end
end
