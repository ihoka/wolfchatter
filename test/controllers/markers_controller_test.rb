require "test_helper"

class MarkersControllerTest < ActionDispatch::IntegrationTest
  TS = { "Accept" => "text/vnd.turbo-stream.html" }.freeze
  EUROPE = { south: 35, west: -10, north: 60, east: 30, zoom: 5 }.freeze

  def get_markers(params = EUROPE, headers: TS)
    get chatroom_markers_path, params: params, headers: headers
  end

  def insert_rooms(count)
    now = Time.current
    Chatroom.insert_all(Array.new(count) { |i|
      { latitude: 40.0 + (i % 100) * 0.01, longitude: 10.0 + (i / 100) * 0.01,
        created_at: now, updated_at: now }
    })
  end

  test "pins reply updates #markers with set markers" do
    get_markers
    assert_response :success
    assert_select "turbo-stream[action=update][target=markers]"
    assert_select "#marker_set[data-controller=marker-set][data-marker-set-mode-value=pins]"
    assert_select "[data-marker-role-value=set]", count: Chatroom.count
  end

  test "clusters reply when dense" do
    Message.delete_all
    Chatroom.delete_all
    total = MapMarkers::PIN_LIMIT + 1
    insert_rooms(total)
    get_markers(EUROPE.merge(zoom: 8))
    assert_response :success
    assert_select "#marker_set[data-marker-set-mode-value=clusters]"
    counts = css_select("[data-cluster]").map { |n| n["data-count"].to_i }
    assert_equal total, counts.sum
  end

  test "titles are escaped" do
    Chatroom.create!(latitude: 45.0, longitude: 10.0, place_name: "<img src=x>")
    get_markers
    assert_not_includes response.body, "<img src=x>"
    assert_includes response.body, "&lt;img"
  end

  test "bad params are 400" do
    [ { zoom: nil }, { zoom: "abc" }, { zoom: 40 }, { zoom: -1 },
      { north: "1e309" }, { west: -200 }, { east: 200 } ].each do |override|
      get_markers(EUROPE.merge(override).compact)
      assert_response :bad_request, "expected 400 for #{override}"
    end
  end

  test "latitude is clamped" do
    get_markers(EUROPE.merge(south: -100, north: 100))
    assert_response :success
  end

  test "html request is 406" do
    get_markers(EUROPE, headers: {})
    assert_response :not_acceptable
  end

  test "reply is not cached" do
    get_markers
    assert_includes response.headers["Cache-Control"], "no-cache"
  end

  # A bug in MapMarkers or the view must surface as an error, not hide behind a 400.
  test "an error while building markers is not a 400" do
    %i[initialize mode].each do |method|
      original = MapMarkers.instance_method(method)
      MapMarkers.define_method(method) { |**| raise ArgumentError, "bug in MapMarkers##{method}" }
      begin
        error = assert_raises(ArgumentError, ActionView::Template::Error) { get_markers }
        assert_equal "bug in MapMarkers##{method}", error.message
      ensure
        MapMarkers.define_method(method, original)
      end
    end
  end

  test "query count is constant" do
    counts = [ 20, MapMarkers::PIN_LIMIT + 50 ].map do |n|
      Message.delete_all
      Chatroom.delete_all
      insert_rooms(n)
      queries = []
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        queries << payload[:sql] unless %w[SCHEMA TRANSACTION].include?(payload[:name])
      end
      get_markers(EUROPE.merge(zoom: 8))
      ActiveSupport::Notifications.unsubscribe(sub)
      queries.size
    end
    counts.each { |c| assert_operator c, :<=, 3 }
  end
end
