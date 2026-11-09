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

  test "creating a room enqueues the job" do
    assert_enqueued_with(job: GeocodeChatroomJob) { Chatroom.create!(latitude: 1, longitude: 2) }
  end

  test "enqueues the job even when the marker broadcast raises" do
    room = Chatroom.new(latitude: 1, longitude: 2)
    room.define_singleton_method(:broadcast_append_to) { |*, **| raise "boom" }
    assert_enqueued_with(job: GeocodeChatroomJob) do
      assert_raises(RuntimeError) { room.save! }
    end
  end

  test "sleeps the throttle once after a real call" do
    stub_request(:get, /nominatim/).to_return(body: { address: { city: "Rome", country: "Italy" } }.to_json)
    assert_equal [ Rails.configuration.x.nominatim.throttle ], sleeps_during(chatrooms(:cluj))
  end

  test "sleeps the throttle once when nothing is found" do
    stub_request(:get, /nominatim/).to_return(body: { error: "Unable to geocode" }.to_json)
    assert_equal [ Rails.configuration.x.nominatim.throttle ], sleeps_during(chatrooms(:cluj))
  end

  test "never sleeps when the place name already exists" do
    assert_empty sleeps_during(chatrooms(:rome))
  end

  private

  def sleeps_during(room)
    sleeps = []
    job = GeocodeChatroomJob.new(room)
    job.define_singleton_method(:sleep) { |seconds| sleeps << seconds }
    job.perform(room)
    sleeps
  end

  test "all geocode jobs share one global concurrency slot" do
    assert_equal 1, GeocodeChatroomJob.concurrency_limit
    keys = Chatroom.where(id: [ :cluj, :rome ].map { ActiveRecord::FixtureSet.identify(_1) }).map { GeocodeChatroomJob.new(_1).concurrency_key }
    assert_equal [ "GeocodeChatroomJob/nominatim" ], keys.uniq
  end

  test "a job for a deleted room is discarded without an API call" do
    room = Chatroom.create!(latitude: 1, longitude: 2)
    clear_enqueued_jobs
    GeocodeChatroomJob.perform_later(room)
    room.delete
    assert_nothing_raised { perform_enqueued_jobs }
    assert_not_requested :get, /nominatim/
  end
end
