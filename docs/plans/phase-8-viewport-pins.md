# Phase 8: Viewport Pins and Clustering Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Map pages carry a fixed amount of pin data however many rooms exist. The server sends the
visible area as pins, or as count clusters when dense. Live updates keep working.

**Architecture:**
- A `MapMarkers` PORO turns a bounding box and a zoom into either a pin list or a grid of clusters,
  using a constant number of indexed queries.
- `GET /chatrooms/markers` renders that result as a Turbo Stream `update` of `#markers`.
- The `map` Stimulus controller fetches on load and after each `moveend`, swaps its layer, and
  applies live rooms from the global stream.

**Tech Stack:** Rails 8.1, PostgreSQL, Turbo Streams, Stimulus, Leaflet 1.9.4 (vendored), Minitest
and Capybara with headless Chrome.

**Spec:** [`docs/superpowers/specs/2026-11-09-viewport-pins-design.md`](../superpowers/specs/2026-11-09-viewport-pins-design.md).
The project spec ([`2026-11-09-wolfchatter-design.md`](../superpowers/specs/2026-11-09-wolfchatter-design.md))
and `CLAUDE.md` still apply wherever this design doesn't change them.

## Global Constraints

- **Values:**
  - `MapMarkers::PIN_LIMIT = 300`
  - `MapMarkers::CELL_PX = 80`
  - cell size in degrees: `360.0 / 2**zoom * (CELL_PX / 256.0)`
  - global grid origin: `cell_x = floor(lng / size)`, `cell_y = floor(lat / size)`
  - `moveend` debounce: 250 ms
  - cluster click: zoom +2, capped at 19
  - `#live_markers` keeps the last 20 elements
  - deep-link zoom: 5
- **Delivery:** no JSON endpoint, no new JS or gem dependencies, no PostGIS. Pins and clusters are
  server-rendered elements with data attributes, delivered as a Turbo Stream.
- **Queries:**
  - every query is bounded by `PIN_LIMIT` and uses the new `(latitude, longitude)` index;
  - a markers request runs **at most 3 SQL queries** whatever the room count;
  - Prosopite stays on and nothing is allow-listed.
- **Choosing pins or clusters is by count, not zoom.** If there are `PIN_LIMIT` or fewer rooms in the
  box, the reply is pins. A small map must look exactly as it does today at every zoom.
- **Lone rooms:** a cluster cell holding one room renders as a pin, never as a "1" bubble.
- **Escaping:** titles reach Leaflet only as text nodes (`textNode`) and never as HTML. Cluster
  counts are integers.
- **Commits:** Conventional Commit prefixes, each ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Branch `phase-8-viewport-pins`.
- **Docs** are written for the product team, with no interview framing.

## Review Focus

1. **Antimeridian.** Panning across the Pacific (west > east) must still show the pins on both
   sides. Owned by Task 1 (model test) and Task 2 (param test).
2. **Zoomed fully out (zoom 0–2), wider than the world.** The client sends west -180 and east 180,
   and the grid is coarsened by arithmetic until it fits `PIN_LIMIT`. There must be no 500 and no
   truncated reply. Owned by Task 1.
3. **Hostile params.** `zoom=abc`, `zoom=40`, `north=1e309`, `west=-200`, or a missing key all give
   400, never 500. Owned by Task 2.
4. **Live room created while a fetch is in flight.** It must not vanish when the reply lands. Owned
   by Task 4 (system test).
5. **Clicking a cluster creates no room.** Owned by Task 4 (system test).

---

### Task 1: `MapMarkers` query object and index

**Files:**
- Create: `db/migrate/<timestamp>_add_location_index_to_chatrooms.rb`
- Create: `app/models/map_markers.rb`
- Test: `test/models/map_markers_test.rb`

**Interfaces:**
- Produces:
  - `MapMarkers.new(south:, west:, north:, east:, zoom:)`. Takes floats and an integer, already
    validated by Task 2.
  - `#mode`, returning `:pins` or `:clusters`.
  - `#pins`, returning an Array of `Chatroom` with only `id, latitude, longitude, place_name`
    selected. It returns `[]` in cluster mode.
  - `#clusters`, returning an Array of `MapMarkers::Cluster = Data.define(:cell_x, :cell_y, :count, :lat, :lng, :chatroom)`.
    `chatroom` is set only when `count == 1`. It returns `[]` in pin mode.
  - `#cell_size`, a Float: the cell size actually used, after coarsening.
  - `MapMarkers.cell_size_for(zoom)`, a Float.
  - Constants `PIN_LIMIT` and `CELL_PX`.

- [ ] **Step 1: Write the failing tests** in `test/models/map_markers_test.rb`. Dense data comes from
  `Chatroom.insert_all` inside the test, never from fixtures. Tests:
  - `test "pins mode returns only rooms inside the box"`: rooms at (46.77, 23.59) and (41.9, 12.49),
    box south 45, west 20, north 48, east 25, zoom 8. Assert `mode == :pins` and that the pins hold
    Cluj only.
  - `test "box crossing the antimeridian queries both sides"`: rooms at lng 179.5 and -179.5, plus one
    at lng 0. West 170, east -170, lat -10..10. Assert two pins, and that the lng-0 room is absent.
  - `test "switches to clusters above PIN_LIMIT"`: insert `PIN_LIMIT + 1` rooms inside a 1°×1° box.
    Assert `mode == :clusters`, `pins == []` and that the counts sum to `PIN_LIMIT + 1`.
  - `test "clusters group on a global grid"`: zoom 4. Put rooms at known coordinates in two cells.
    Assert each cluster's `cell_x == (lng / MapMarkers.cell_size_for(4)).floor` and that the counts
    are right.
  - `test "lone room cell carries its chatroom"`: in cluster mode, one isolated room far from a dense
    group. Assert its cluster has `count == 1` and `chatroom.title` loaded, and that the dense cluster
    has `chatroom == nil`.
  - `test "world box coarsens cells to fit PIN_LIMIT"`: zoom 3, box -90/-180/90/180.
    `((360 / cell_size).ceil + 1) * ((180 / cell_size).ceil + 1) <= PIN_LIMIT`, and
    `cell_size >= MapMarkers.cell_size_for(3)`.
  - `test "runs at most 3 queries"`: count `sql.active_record` notifications (excluding `SCHEMA`) for
    `MapMarkers.new(...).tap { _1.pins; _1.clusters }` in both modes. Each must be `<= 3`.
- [ ] **Step 2: Run them.** `bin/rails test test/models/map_markers_test.rb` fails with
  `uninitialized constant MapMarkers`.
- [ ] **Step 3: Write the migration** `add_index :chatrooms, [:latitude, :longitude]` and run
  `bin/rails db:migrate`. `db/schema.rb` must show the index.
- [ ] **Step 4: Implement `MapMarkers`.**
  - **Longitude filter:** `west <= east` gives `longitude BETWEEN west AND east`. Otherwise use
    `longitude >= west OR longitude <= east`.
  - **Pins:** select `limit(PIN_LIMIT + 1)`. If there are `<= PIN_LIMIT` rows, the mode is `:pins`.
  - **Cell size:** start at `cell_size_for(zoom)`, then double it while
    `((east_span / size).ceil + 1) * (((north - south) / size).ceil + 1) > PIN_LIMIT`. The east span
    is `east - west`, plus 360 when that is negative. This is arithmetic only, with no query in the
    loop.
  - **Clusters:** one `GROUP BY FLOOR(longitude / size), FLOOR(latitude / size)` query selecting
    `COUNT(*)`, `AVG(latitude)`, `AVG(longitude)` and `MIN(id)`. Then one
    `Chatroom.where(id: lone_ids)` query, indexed by id.
  - Memoize, so `#mode`, `#pins` and `#clusters` never re-query.
- [ ] **Step 5: Run the tests.** `bin/rails test test/models/map_markers_test.rb` must show 0
  failures. Then `bin/rails test` must be green.
- [ ] **Step 6: Commit.** `feat: add MapMarkers viewport query with grid clustering`

### Task 2: `GET /chatrooms/markers` endpoint

**Files:**
- Modify: `config/routes.rb`. Add `get "chatrooms/markers", to: "markers#index", as: :chatroom_markers`
  **above** `resources :chatrooms`.
- Create: `app/controllers/markers_controller.rb`
- Create: `app/views/markers/index.turbo_stream.erb`
- Create: `app/views/chatrooms/_cluster.html.erb`
- Modify: `app/views/chatrooms/_marker.html.erb`. Add the optional locals `role:` and `cell:`.
- Test: `test/controllers/markers_controller_test.rb`

**Interfaces:**
- Consumes: `MapMarkers` from Task 1.
- Produces the reply markup that Task 4's JS reads:
  - **Reply:** exactly one `<turbo-stream action="update" target="markers">`. Its template is a single
    `<div id="marker_set" data-controller="marker-set" data-marker-set-mode-value="pins|clusters" data-marker-set-cell-size-value="<float>">`.
  - **Pin children:** use the `_marker` partial with `role: "set"`, which gives
    `data-marker-role-value="set"`. In cluster mode, lone pins also carry `data-cell-x` and
    `data-cell-y`.
  - **Cluster children:** use `_cluster`. Each is
    `<div data-cluster data-lat data-lng data-count data-cell-x data-cell-y></div>`.
  - **`_marker` locals:** `role:` defaults to `"live"` and renders as `data-marker-role-value`. Values
    are `"live"`, `"panel"` and `"set"`. `cell:` is an optional `[x, y]`. The existing `id_suffix:`
    local stays.

- [ ] **Step 1: Write the failing tests.** All requests use
  `headers: { "Accept" => "text/vnd.turbo-stream.html" }` unless noted. Tests:
  - `test "pins reply updates #markers with set markers"`: the box around Europe returns 200. Assert
    `turbo-stream[action=update][target=markers]`, `#marker_set[data-marker-set-mode-value=pins]`,
    and one `[data-marker-role-value=set]` per fixture room.
  - `test "clusters reply when dense"`: `insert_all` `PIN_LIMIT + 1` rooms. Assert mode `clusters`
    and that the `[data-cluster]` counts sum to the total.
  - `test "titles are escaped"`: a room with `place_name: "<img src=x>"`. Assert the body has no
    `<img src=x>` and has `&lt;img`.
  - `test "bad params are 400"`, looping over each of these params, each with a 400 response:
    - missing `zoom`
    - `zoom=abc`
    - `zoom=40`
    - `zoom=-1`
    - `north=1e309`
    - `west=-200`
    - `east=200`
  - `test "latitude is clamped"`: `south=-100&north=100` returns 200.
  - `test "html request is 406"`: no Accept header returns `:not_acceptable`.
  - `test "reply is not cached"`: `Cache-Control` includes `no-cache`.
  - `test "query count is constant"`: count the SQL for a request at 20 rooms and at
    `PIN_LIMIT + 50` rooms. Both must be `<= 3`.
- [ ] **Step 2: Run them.** `bin/rails test test/controllers/markers_controller_test.rb` fails with a
  routing error.
- [ ] **Step 3: Implement `MarkersController#index`.**
  - **Parse params:** use `Float(params.require(:south))`, and the same for `west`, `north` and
    `east`. Use `Integer(params.require(:zoom), 10)`.
  - **Validate:** lng must be in -180..180, zoom in 0..19, and every value finite. Latitude is clamped
    to -90..90.
  - **Errors:** rescue `ArgumentError`, `TypeError` and `ActionController::ParameterMissing`, then
    `head :bad_request`.
  - **Response:** call `expires_now`. Use
    `respond_to { format.turbo_stream; format.any { head :not_acceptable } }`, following the
    messages controller.
- [ ] **Step 4: Run the tests.** The controller tests must be green, and then `bin/rails test`. The
  existing marker tests must still pass, because `role` defaults to `"live"`.
- [ ] **Step 5: Commit.** `feat: serve viewport markers as a Turbo Stream`

### Task 3: Map page stops rendering every room

**Files:**
- Modify: `app/controllers/chatrooms_controller.rb`. Remove `@chatrooms` from `index` and `show`.
- Modify: `app/views/chatrooms/index.html.erb` and `show.html.erb`. Stop passing `chatrooms:`.
- Modify: `app/views/chatrooms/_map_page.html.erb`:
  - `#markers` starts empty;
  - add `<div id="live_markers" hidden></div>`;
  - add `data-map-markers-url-value="<%= chatroom_markers_path %>"`;
  - the center value is `[chatroom.latitude, chatroom.longitude]` when `chatroom`, else
    `[48.0, 15.0]`; the zoom stays 5.
- Modify: `app/views/chatrooms/_panel.html.erb`. The panel marker passes `role: "panel"`.
- Modify: `app/models/chatroom.rb`:
  - the create broadcast appends to `"live_markers"` (role default `"live"`);
  - the title broadcast keeps replacing `dom_id(self, :marker)`, but renders with `role: "set"`.
- Test: `test/controllers/chatrooms_controller_test.rb`, `test/models/chatroom_test.rb`.

**Interfaces:**
- Produces the DOM that Task 4 relies on:
  - `#markers` and `#live_markers`;
  - `data-map-markers-url-value`;
  - a center value that follows a deep-linked room;
  - live markers with role `live`, the panel marker with role `panel`, and title-replace markers
    with role `set`.

- [ ] **Step 1: Update and add the failing tests.**
  - Replace `test "index renders a marker per room"` with
    `test "index renders no room markers"`. It asserts `#markers` is empty, `#live_markers` exists,
    and `#map_container[data-map-markers-url-value=?]` equals `chatroom_markers_path`.
  - `test "show centres the map on its room"`: `data-map-center-value` is `[46.770439, 23.591423]`
    for Cluj, and the panel marker has `data-marker-role-value=panel`.
  - In `chatroom_test.rb`, assert the create broadcast targets `live_markers`. Use
    `assert_turbo_stream_broadcasts "chatrooms"` and inspect the target. Also assert the title
    broadcast renders `data-marker-role-value="set"`.
- [ ] **Step 2: Run them** and watch them fail.
- [ ] **Step 3: Implement** the file changes above.
- [ ] **Step 4: Run the tests.** `bin/rails test` must be green. System tests that count
  `.leaflet-marker-icon` are expected to fail until Task 4. Note them in the report; don't change
  them here.
- [ ] **Step 5: Commit.** `refactor: map page loads pins per viewport, not all rooms`

### Task 4: Map controller fetches the viewport, draws clusters and applies live rooms

**Files:**
- Create: `app/javascript/controllers/marker_set_controller.js`
- Modify:
  - `app/javascript/controllers/marker_controller.js`. Add a `role` value to the event detail.
  - `app/javascript/controllers/map_controller.js`
  - `app/views/chatrooms/_map_page.html.erb`. Add the `data-action` for `marker-set:load@window`.
- Test: `test/system/map_page_test.rb`, `live_updates_test.rb` and `rooms_test.rb`. Update the
  existing tests and add `test/system/clusters_test.rb`.

**Interfaces:**
- Consumes: the reply markup from Task 2 and the DOM from Task 3.
- **`marker-set` controller:** on connect it reads its children and dispatches `marker-set:load` on
  `window` with the detail
  `{ mode, cellSize, pins: [{id, lat, lng, title, url, cell}], clusters: [{lat, lng, count, cellX, cellY}] }`.
- **`marker:connect`:** its detail gains `role`.
- **`map` controller behaviour:**
  - **Fetching:**
    - after setup, and on `moveend` debounced 250 ms, call `fetch(markersUrl + bbox query)` with
      `Accept: text/vnd.turbo-stream.html` and an `AbortController` that aborts the previous request;
    - pass the reply to `Turbo.renderStreamMessage`;
    - longitudes are wrapped. If the bounds span 360° or more, send west -180 and east 180.
  - **Layers:**
    - **`panelLayer`:** the panel-role pins. It is never cleared by a fetch.
    - **`setLayer`:** fetched pins and clusters.
    - On `marker-set:load`, build a new layer, add it, then remove the old one. Skip pins whose id is
      in `panelLayer`.
    - Remember `mode`, `cellSize`, and clusters keyed by `"x,y"`.
  - **Live, role `live`, unknown id:**
    - **Pins mode:** add the pin to `setLayer` if it is inside `map.getBounds()`.
    - **Clusters mode:**
      - compute the cell from the global formula;
      - if a cluster exists there, increment its count and re-render its icon;
      - if a lone pin is there, replace it with a cluster of count 2;
      - otherwise add a lone pin.
    - Record `{detail, receivedAt}` in a list capped at 20. After each swap, re-apply the entries
      whose `receivedAt` is later than that fetch's `requestedAt`.
    - Prune `#live_markers` to its last 20 children.
  - **Roles `set` and `panel` with a known id:** re-title only (existing `retitle`). Role `panel`
    with an unknown id adds the pin to `panelLayer`. Role `set` with an unknown id is ignored.
  - **Cluster icon:** an `L.divIcon` holding a text count, with Tailwind classes, round, readable on
    OSM tiles. Its size is 32, 40 or 48 px for counts under 10, under 100, and above.
  - **Cluster click:** `map.setView(cluster latlng, Math.min(map.getZoom() + 2, 19))`. It must not
    reach the map's room-creating click handler.
  - **Map click guard:** the existing 300 ms double-click guard and the `form.requestSubmit` flow stay
    as they are.

- [ ] **Step 1: Update and write the failing system tests.**
  - Existing tests that count `.leaflet-marker-icon` against `Chatroom.count` keep working through
    the sparse-map path. Fix any that relied on markers rendered by the server.
  - `clusters_test.rb`. Seed with `Chatroom.insert_all` 400 rooms in a 2°×2° box around (45, 10).
    Tests:
    - `test "dense area shows a cluster with a count"`: visit the root and assert
      `.leaflet-marker-icon` with text matching `/\d+/`, and that the counts on screen sum to at
      least 400.
    - `test "clicking a cluster zooms in and creates no room"`: record the zoom, click the cluster,
      and assert `#map_container[data-map-current-zoom]` increased. `Chatroom.count` is unchanged.
    - `test "zooming in far enough shows pins"`: click clusters until no cluster is left in view, and
      assert `.leaflet-marker-icon[title]` is present.
  - Additions to `live_updates_test.rb`:
    - `test "off-screen new room does not appear in pins mode"`: the watcher is on the root (sparse,
      pins mode). Create a room with `Chatroom.create!` at a point outside the watcher's bounds, which
      you can find with `page.evaluate_script` on the map. Assert the pin count is unchanged after the
      broadcast. Then create one inside the bounds and assert the count went up by one.
    - `test "new room raises a cluster count live"`: dense seed, watcher on the root, then
      `Chatroom.create!` inside the cluster. Assert the cluster's count text went up by 1.
    - `test "room created during a fetch survives the swap"`: delay the fetch from the page by
      patching `window.fetch` through `page.execute_script` to wait 500 ms, then pan the map. Create
      an in-view room during the delay and assert its pin is present after the reply lands.
  - `map_page_test.rb`: `test "deep link centres on its room"`. Visit Rome's room path, then assert
    the Leaflet center (read through `evaluate_script`, `#map.leafletMap.getCenter()`) is within 0.01
    of Rome.
- [ ] **Step 2: Run them.** `bin/rails test:system` shows the new tests failing.
- [ ] **Step 3: Implement** the behaviour above. Keep `textNode` for every title.
- [ ] **Step 4: Run all tests.** `bin/rails test:system` must be green three times in a row
  (`for i in 1 2 3; do bin/rails test:system || break; done`). Then run `bin/rails test`. Look for
  JS errors in the browser console logs (`goog:loggingPrefs`).
- [ ] **Step 5: Commit.** `feat: fetch pins per viewport and cluster dense areas on the map`

### Task 5: Benchmark and docs

**Files:**
- Modify:
  - `docs/prd.md`:
    - FR-1: the map shows the pins in view, grouped into count clusters when dense;
    - FR-8: the live rules from the spec's Goals;
    - drop "Pin clustering" from the non-goals;
    - drop the "Unbounded pin loading" risk;
    - rewrite the global-stream paragraph for `#live_markers` and viewport fetches.
  - `docs/superpowers/specs/2026-11-09-wolfchatter-design.md`: the "all existing pins" wording and
    the clustering non-goal. Link the viewport-pins design.
  - `CLAUDE.md`, "Live map pins" bullet:
    - pins and clusters are marker elements fetched per viewport as a Turbo Stream into `#markers`;
    - live pins arrive in `#live_markers`;
    - roles are `live`, `panel` and `set`;
    - there is still no JSON endpoint.
  - `docs/review/notes.md`. Move Q1 into "Fixed" with the commits and benchmark figures, and remove
    the Q1 bullet from "What I'd do with more time".
  - `README.md`:
    - features;
    - the architecture diagram (the markers fetch);
    - the data-model and streams bullets;
    - the decisions table, including the "Pins as marker elements" row's trade-off and a new row for
      server-side clustering against markercluster;
    - known limitations.
  - `docs/plans/00-overview.md`. Add a phase 8 row.

- [ ] **Step 1: Benchmark** with a throwaway script in `$CLAUDE_JOB_DIR/tmp`, not committed.
  - Insert 10,000 rooms spread across Europe in the development database.
  - Measure the size and time of `GET /` and of a world-view markers request (zoom 3, -90/-180/90/180)
    with `bin/rails runner` and `ActionDispatch::Integration::Session`.
  - Compare against the Q1 figures: 3.7 MB and about 220 ms.
  - Delete the seeded rooms afterwards.
- [ ] **Step 2: Update each doc listed above.** Every claim must match the code, and every figure
  must come from Step 1.
- [ ] **Step 3: Verify.**
  - `bin/review` is green, with 100% line coverage and no RuboCop or Brakeman findings.
  - Every link in the changed docs resolves.
  - `grep -inE 'interview|candidate'` over `docs README.md CLAUDE.md` returns nothing.
- [ ] **Step 4: Commit.** `docs: document viewport pins and clustering`
- [ ] **Step 5: Push and open the PR.** The PR links this plan and the design doc and summarises the
  rulings.
