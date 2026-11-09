require "application_system_test_case"

class MessagesTest < ApplicationSystemTestCase
  test "set a name once, then post messages" do
    visit chatroom_path(chatrooms(:rome))
    fill_in placeholder: "write your user name here", with: "Ana"
    click_on "Save name"
    assert_text "Chatting as Ana"
    fill_in placeholder: "write message here", with: "Ciao!"
    click_on "Submit"
    within("##{dom_id(chatrooms(:rome), :messages)}") { assert_text "Ciao!" }
    assert_field placeholder: "write message here", with: ""
    visit chatroom_path(chatrooms(:cluj))
    assert_text "Chatting as Ana"
  end
end
