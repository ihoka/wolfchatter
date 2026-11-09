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
end
