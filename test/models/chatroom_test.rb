require "test_helper"
require "turbo/broadcastable/test_helper"

class ChatroomTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  test "valid with coordinates in range" do
    assert Chatroom.new(latitude: 46.77, longitude: 23.59).valid?
  end

  test "requires coordinates" do
    room = Chatroom.new
    assert_not room.valid?
    assert_includes room.errors.attribute_names, :latitude
    assert_includes room.errors.attribute_names, :longitude
  end

  test "rejects out-of-range coordinates" do
    assert_not Chatroom.new(latitude: 90.000001, longitude: 0).valid?
    assert_not Chatroom.new(latitude: 0, longitude: -180.000001).valid?
    assert_not Chatroom.new(latitude: 0, longitude: 181).valid?
    assert Chatroom.new(latitude: -90, longitude: 180).valid?
  end

  test "title falls back to Chatroom <id>" do
    room = chatrooms(:cluj)
    assert_equal "Chatroom #{room.id}", room.title
  end

  test "title uses place name when present" do
    assert_equal "Rome, Italy", chatrooms(:rome).title
    assert_equal "Chatroom #{chatrooms(:rome).id}", chatrooms(:rome).tap { _1.place_name = " " }.title
  end

  test "creating a room broadcasts its marker to the live markers" do
    streams = capture_turbo_stream_broadcasts("chatrooms") { Chatroom.create!(latitude: 1, longitude: 2) }
    assert_equal 1, streams.size
    assert_equal "append", streams.first["action"]
    assert_equal "live_markers", streams.first["target"]
    marker = streams.first.at_css("[data-controller=marker]")
    assert_match(/\Alive_marker_chatroom_\d+\z/, marker["id"])
    assert_equal "live", marker["data-marker-role-value"]
  end

  test "a new place name broadcasts the title and both marker replaces" do
    room = chatrooms(:cluj)
    assert_turbo_stream_broadcasts(room, count: 1) do
      streams = capture_turbo_stream_broadcasts("chatrooms") { room.update!(place_name: "Cluj-Napoca, Romania") }
      assert_equal 2, streams.size
      assert_equal %w[replace replace], streams.map { _1["action"] }
      ids = [ ActionView::RecordIdentifier.dom_id(room, :marker), ActionView::RecordIdentifier.dom_id(room, :live_marker) ]
      assert_equal ids, streams.map { _1["target"] }
      streams.each do |stream|
        assert_equal "set", stream.at_css("[data-controller=marker]")["data-marker-role-value"]
      end
      assert_equal ids, streams.map { _1.at_css("[data-controller=marker]")["id"] }
    end
  end

  test "updating other attributes broadcasts nothing" do
    room = chatrooms(:cluj)
    assert_no_turbo_stream_broadcasts(room) do
      assert_no_turbo_stream_broadcasts("chatrooms") { room.update!(latitude: 10) }
    end
  end

  test "place names longer than 120 characters are invalid" do
    assert_not chatrooms(:cluj).tap { _1.place_name = "a" * 121 }.valid?
  end

  test "recent_messages defaults to the newest 100" do
    room = chatrooms(:rome)
    now = Time.current
    rows = 101.times.map do |i|
      { chatroom_id: room.id, author_name: "A", body: "m#{i}", created_at: now + i.seconds, updated_at: now }
    end
    Message.insert_all(rows)
    recent = room.recent_messages
    assert_equal 100, recent.size
    assert_equal "m1", recent.first.body
    assert_equal "m100", recent.last.body
    assert_not_includes recent.map(&:body), "m0"
  end
end
