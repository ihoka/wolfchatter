require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ] do |options|
    options.binary = ENV["CHROME_BIN"] if ENV["CHROME_BIN"]
    options.add_option("goog:loggingPrefs", { browser: "ALL" })
  end

  private

  # 400 rooms on a 20x20 grid in a 2°x2° box around (45, 10): enough to put the default view
  # in cluster mode (more than MapMarkers::PIN_LIMIT rooms in the box).
  def seed_dense_area
    now = Time.current
    rows = (0...20).flat_map do |i|
      (0...20).map do |j|
        { latitude: (44.0 + i * 0.1).round(6), longitude: (9.0 + j * 0.1).round(6),
          place_name: "Dense #{i}-#{j}", created_at: now, updated_at: now }
      end
    end
    Chatroom.insert_all(rows)
  end

  def map_script(expression)
    page.evaluate_script("(() => { const map = document.getElementById('map').leafletMap; return #{expression} })()")
  end

  def cluster_counts
    all(".map-cluster").map { |el| Integer(el.text) }
  end

  # Marks the current fetched set so a test can wait until the next fetch has been drawn.
  def mark_marker_set_stale
    assert_selector "#marker_set", visible: :all
    page.execute_script("document.getElementById('marker_set').dataset.stale = ''")
  end

  def assert_marker_set_refreshed
    assert_selector "#marker_set:not([data-stale])", visible: :all
  end

  def assert_no_js_errors
    errors = page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" }
    assert_empty errors.map(&:message)
  end
end
