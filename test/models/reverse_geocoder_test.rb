require "test_helper"

class ReverseGeocoderTest < ActiveSupport::TestCase
  def stub_nominatim(body:, status: 200)
    stub_request(:get, %r{\Ahttps://nominatim\.openstreetmap\.org/reverse})
      .to_return(status:, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  test "formats city and country and sends an identifying user agent" do
    stub_nominatim(body: { address: { city: "Cluj-Napoca", country: "Romania" }, display_name: "x" })
    assert_equal "Cluj-Napoca, Romania", ReverseGeocoder.new.place_name(46.77, 23.59)
    assert_requested :get, %r{reverse\?.*lat=46\.77.*lon=23\.59}, headers: { "User-Agent" => /Wolfchatter/, "Accept-Language" => "en" }
  end

  test "falls back to town, then display_name" do
    stub_nominatim(body: { address: { town: "Sibiu", country: "Romania" } })
    assert_equal "Sibiu, Romania", ReverseGeocoder.new.place_name(45.79, 24.15)
    stub_nominatim(body: { address: {}, display_name: "Somewhere" })
    assert_equal "Somewhere", ReverseGeocoder.new.place_name(1, 1)
  end

  test "returns nil when nothing is found" do
    stub_nominatim(body: { error: "Unable to geocode" })
    assert_nil ReverseGeocoder.new.place_name(40.0, 5.0)
  end

  test "returns nil on timeouts, server errors and bad JSON" do
    stub_request(:get, /nominatim/).to_timeout
    assert_nil ReverseGeocoder.new.place_name(1, 1)
    stub_request(:get, /nominatim/).to_return(status: 503, body: "")
    assert_nil ReverseGeocoder.new.place_name(1, 1)
    stub_request(:get, /nominatim/).to_return(status: 200, body: "not json")
    assert_nil ReverseGeocoder.new.place_name(1, 1)
  end

  test "returns nil on connection-level failures" do
    [ EOFError, IOError, Net::HTTPBadResponse, Zlib::DataError ].each do |error|
      stub_request(:get, /nominatim/).to_raise(error)
      assert_nil ReverseGeocoder.new.place_name(1, 1), "expected nil for #{error}"
    end
  end

  test "truncates very long names to 120 characters" do
    stub_nominatim(body: { address: {}, display_name: "a" * 300 })
    assert_equal 120, ReverseGeocoder.new.place_name(1, 1).length
  end
end
