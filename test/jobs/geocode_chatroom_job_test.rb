require "test_helper"

class GeocodeChatroomJobTest < ActiveJob::TestCase
  test "stores the place name" do
    stub_request(:get, /nominatim/).to_return(body: { address: { city: "Rome", country: "Italy" } }.to_json)
    room = chatrooms(:cluj)
    GeocodeChatroomJob.perform_now(room)
    assert_equal "Rome, Italy", room.reload.place_name
  end

  test "keeps the fallback title when nothing is found" do
    stub_request(:get, /nominatim/).to_return(body: { error: "Unable to geocode" }.to_json)
    room = chatrooms(:cluj)
    GeocodeChatroomJob.perform_now(room)
    assert_nil room.reload.place_name
    assert_equal "Chatroom #{room.id}", room.title
  end

  test "does not call the API when a place name exists" do
    GeocodeChatroomJob.perform_now(chatrooms(:rome))
    assert_not_requested :get, /nominatim/
  end

  test "place names longer than 120 characters are invalid" do
    assert_not chatrooms(:cluj).tap { _1.place_name = "a" * 121 }.valid?
  end

  test "creating a room enqueues the job" do
    assert_enqueued_with(job: GeocodeChatroomJob) { Chatroom.create!(latitude: 1, longitude: 2) }
  end
end
