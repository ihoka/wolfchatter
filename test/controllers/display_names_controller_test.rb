require "test_helper"

class DisplayNamesControllerTest < ActionDispatch::IntegrationTest
  test "setting a name stores it and swaps in the compose area" do
    patch display_name_path, params: { display_name: { name: " Ana " }, chatroom_id: chatrooms(:cluj).id },
                             as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=replace][target=?]", dom_id(chatrooms(:cluj), :compose)
    assert_includes response.body, "Chatting as"
    get chatroom_path(chatrooms(:cluj))
    assert_select "##{dom_id(chatrooms(:cluj), :compose)}", text: /Chatting as\s+Ana/
  end

  test "an invalid name is rejected" do
    patch display_name_path, params: { display_name: { name: "a" * 41 }, chatroom_id: chatrooms(:cluj).id },
                             as: :turbo_stream
    assert_response :unprocessable_content
  end

  test "an invalid name replaces the form with errors even when a name exists" do
    patch display_name_path, params: { display_name: { name: "Ana" }, chatroom_id: chatrooms(:cluj).id }, as: :turbo_stream
    patch display_name_path, params: { display_name: { name: "a" * 41 }, chatroom_id: chatrooms(:cluj).id }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_select "input[placeholder='write your user name here']"
    assert_select "[role=alert]"
  end

  test "changing the name forgets it" do
    patch display_name_path, params: { display_name: { name: "Ana" }, chatroom_id: chatrooms(:cluj).id }, as: :turbo_stream
    delete display_name_path, params: { chatroom_id: chatrooms(:cluj).id }, as: :turbo_stream
    get chatroom_path(chatrooms(:cluj))
    assert_select "input[placeholder='write your user name here']"
  end

  test "a name with markup is rendered escaped" do
    patch display_name_path, params: { display_name: { name: "<b>x</b>" }, chatroom_id: chatrooms(:cluj).id }, as: :turbo_stream
    get chatroom_path(chatrooms(:cluj))
    assert_select "##{dom_id(chatrooms(:cluj), :compose)} b", count: 0
    assert_includes response.body, "&lt;b&gt;x&lt;/b&gt;"
  end

  test "a tampered cookie is treated as no name" do
    cookies[:display_name] = "tampered"
    get chatroom_path(chatrooms(:cluj))
    assert_response :success
    assert_select "input[placeholder='write your user name here']"
  end

  test "a plain html request does not error" do
    patch display_name_path, params: { display_name: { name: "Ana" }, chatroom_id: chatrooms(:cluj).id }
    assert_response :not_acceptable
  end
end
