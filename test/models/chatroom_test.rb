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

  test "creating a room broadcasts its marker" do
    assert_turbo_stream_broadcasts("chatrooms", count: 1) do
      Chatroom.create!(latitude: 1, longitude: 2)
    end
  end
end
