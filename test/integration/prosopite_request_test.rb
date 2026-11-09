require "test_helper"

# Proves Prosopite's middleware raises for an N+1 inside a real request. The same
# middleware serves Puma in system tests and Capybara re-raises server errors,
# so system tests are covered by the same path.
class ProsopiteRequestTest < ActionDispatch::IntegrationTest
  class N1ProbeController < ActionController::Base
    def show
      Chatroom.all.each { |room| room.messages.to_a }
      head :ok
    end
  end

  test "an N+1 inside a request raises from the request call" do
    Chatroom.create!(latitude: 1, longitude: 1)

    with_routing do |set|
      set.draw { get "/n1" => "prosopite_request_test/n1_probe#show" }
      assert_raises(Prosopite::NPlusOneQueriesError) { get "/n1" }
    end
  end
end
