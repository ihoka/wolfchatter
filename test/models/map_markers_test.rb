require "test_helper"

class MapMarkersTest < ActiveSupport::TestCase
  setup do
    Message.delete_all
    Chatroom.delete_all
  end

  def room(lat, lng, place_name: nil)
    now = Time.current
    Chatroom.insert_all([ { latitude: lat, longitude: lng, place_name: place_name,
                            created_at: now, updated_at: now } ], returning: %w[id]).first["id"]
  end

  def rooms(points)
    now = Time.current
    Chatroom.insert_all(points.map { |lat, lng|
      { latitude: lat, longitude: lng, created_at: now, updated_at: now }
    })
  end

  def markers(south:, west:, north:, east:, zoom:)
    MapMarkers.new(south: south, west: west, north: north, east: east, zoom: zoom)
  end

  test "pins mode returns only rooms inside the box" do
    cluj = room(46.77, 23.59)
    room(41.9, 12.49)
    m = markers(south: 45.0, west: 20.0, north: 48.0, east: 25.0, zoom: 8)

    assert_equal :pins, m.mode
    assert_equal [ cluj ], m.pins.map(&:id)
    assert_equal [], m.clusters
  end

  test "box crossing the antimeridian queries both sides" do
    east_side = room(0.0, 179.5)
    west_side = room(0.0, -179.5)
    room(0.0, 0.0)
    m = markers(south: -10.0, west: 170.0, north: 10.0, east: -170.0, zoom: 5)

    assert_equal :pins, m.mode
    assert_equal [ east_side, west_side ].sort, m.pins.map(&:id).sort
  end

  test "switches to clusters above PIN_LIMIT" do
    rooms((0..MapMarkers::PIN_LIMIT).map { |i| [ 10.0 + (i % 17) * 0.05, 20.0 + (i / 17) * 0.05 ] })
    m = markers(south: 10.0, west: 20.0, north: 11.0, east: 21.0, zoom: 8)

    assert_equal :clusters, m.mode
    assert_equal [], m.pins
    assert_equal MapMarkers::PIN_LIMIT + 1, m.clusters.sum(&:count)
  end

  test "clusters group on a global grid" do
    size = MapMarkers.cell_size_for(4)
    # Two cells: three rooms near (0.1, 0.1), two near (30.1, 40.1), plus filler to exceed the limit
    # elsewhere inside the box so the mode is clusters.
    pts = [ [ 0.1, 0.1 ], [ 0.12, 0.11 ], [ 0.11, 0.13 ], [ 30.1, 40.1 ], [ 30.12, 40.11 ] ]
    pts += Array.new(MapMarkers::PIN_LIMIT) { [ 60.0, 100.0 ] }
    rooms(pts)
    m = markers(south: -10.0, west: -10.0, north: 70.0, east: 110.0, zoom: 4)

    assert_equal :clusters, m.mode
    assert_equal size, m.cell_size
    by_cell = m.clusters.index_by { |c| [ c.cell_x, c.cell_y ] }
    a = by_cell.fetch([ (0.1 / size).floor, (0.1 / size).floor ])
    b = by_cell.fetch([ (40.1 / size).floor, (30.1 / size).floor ])
    assert_equal 3, a.count
    assert_equal 2, b.count
    assert_in_delta 0.11, a.lng, 0.01
    assert_kind_of Float, a.lat
  end

  test "lone room cell carries its chatroom" do
    lone = room(0.5, 0.5, place_name: "Lonely")
    rooms(Array.new(MapMarkers::PIN_LIMIT) { [ 50.0, 50.0 ] })
    m = markers(south: -5.0, west: -5.0, north: 55.0, east: 55.0, zoom: 6)

    assert_equal :clusters, m.mode
    single = m.clusters.find { |c| c.count == 1 }
    assert_equal lone, single.chatroom.id
    assert_equal "Lonely", single.chatroom.title
    dense = m.clusters.find { |c| c.count == MapMarkers::PIN_LIMIT }
    assert_nil dense.chatroom
  end

  test "world box coarsens cells to fit PIN_LIMIT" do
    rooms(Array.new(MapMarkers::PIN_LIMIT + 1) { |i| [ -80.0 + i % 160, -170.0 + (i * 7) % 340 ] })
    m = markers(south: -90.0, west: -180.0, north: 90.0, east: 180.0, zoom: 3)
    size = m.cell_size

    assert_equal :clusters, m.mode
    assert_operator ((360 / size).ceil + 1) * ((180 / size).ceil + 1), :<=, MapMarkers::PIN_LIMIT
    assert_operator size, :>=, MapMarkers.cell_size_for(3)
    assert_equal MapMarkers::PIN_LIMIT + 1, m.clusters.sum(&:count)
  end

  test "runs at most 3 queries" do
    room(0.0, 0.0)
    pins_count = count_queries { markers(south: -1.0, west: -1.0, north: 1.0, east: 1.0, zoom: 8).tap { _1.pins; _1.clusters } }
    rooms(Array.new(MapMarkers::PIN_LIMIT) { [ 0.0, 0.0 ] })
    clusters_count = count_queries { markers(south: -1.0, west: -1.0, north: 1.0, east: 1.0, zoom: 8).tap { _1.pins; _1.clusters } }

    assert_operator pins_count, :<=, 3
    assert_operator clusters_count, :<=, 3
  end

  private

  def count_queries
    n = 0
    sub = ->(*, payload) { n += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(sub, "sql.active_record") { yield }
    n
  end
end
