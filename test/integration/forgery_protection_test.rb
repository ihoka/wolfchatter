require "test_helper"

class ForgeryProtectionTest < ActionDispatch::IntegrationTest
  test "token from the root page still works for POST /chatrooms after a show visit" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    get root_path
    token = css_select("#new_chatroom_form input[name=authenticity_token]").first["value"]
    assert_predicate token, :present?

    get chatroom_path(chatrooms(:rome))
    assert_response :success

    post chatrooms_path, params: { authenticity_token: token, chatroom: { latitude: 47, longitude: 15 } }
    assert_response :see_other

    post chatrooms_path, params: { chatroom: { latitude: 47, longitude: 15 } }
    assert_response :unprocessable_entity
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
