require "test_helper"

class DisplayNameTest < ActiveSupport::TestCase
  test "strips and accepts up to 40 characters" do
    assert_equal "Ana", DisplayName.new(name: "  Ana ").name
    assert DisplayName.new(name: "a" * 40).valid?
    assert_not DisplayName.new(name: "a" * 41).valid?
    assert_not DisplayName.new(name: "   ").valid?
  end
end
