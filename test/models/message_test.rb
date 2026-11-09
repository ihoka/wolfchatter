require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "strips author and body" do
    message = chatrooms(:cluj).messages.create!(author_name: "  Ana  ", body: "  hi  ")
    assert_equal "Ana", message.author_name
    assert_equal "hi", message.body
  end

  test "rejects blank or whitespace-only body" do
    assert_not chatrooms(:cluj).messages.build(author_name: "Ana", body: "   ").valid?
  end

  test "rejects body over 1000 characters" do
    assert chatrooms(:cluj).messages.build(author_name: "Ana", body: "a" * 1000).valid?
    assert_not chatrooms(:cluj).messages.build(author_name: "Ana", body: "a" * 1001).valid?
  end

  test "rejects missing or over-long author" do
    assert_not chatrooms(:cluj).messages.build(author_name: " ", body: "hi").valid?
    assert_not chatrooms(:cluj).messages.build(author_name: nil, body: "hi").valid?
    assert_not chatrooms(:cluj).messages.build(author_name: "a" * 41, body: "hi").valid?
  end

  test "recent_messages returns the newest N oldest-first" do
    room = chatrooms(:rome)
    3.times { |i| room.messages.create!(author_name: "A", body: "m#{i}", created_at: i.minutes.from_now) }
    assert_equal %w[m1 m2], room.recent_messages(2).map(&:body)
  end
end
