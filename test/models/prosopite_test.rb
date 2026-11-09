require "test_helper"

class ProsopiteTest < ActiveSupport::TestCase
  test "an N+1 query raises in the test environment" do
    # test_helper already started a scan in setup; end it so this test owns a fresh one.
    Prosopite.finish

    assert_raises(Prosopite::NPlusOneQueriesError) do
      Prosopite.scan { Chatroom.all.each { |room| room.messages.to_a } }
    end
  end
end
