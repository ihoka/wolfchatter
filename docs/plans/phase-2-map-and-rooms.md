# Phase 2 — Map & Rooms Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Leaflet/OpenStreetMap map where clicking empty space creates a chatroom (pin + panel
switch) and clicking a pin switches the panel, with the URL following the selected room.

**Architecture:** Server-rendered and Hotwire-only. Rooms render as invisible *marker elements*
(data attributes) that a `marker` Stimulus controller announces on `window`; a `map` controller
owns Leaflet, registers announced markers (deduped by room id) and turns map clicks into a hidden
form submission. The panel is a `turbo-frame` with `data-turbo-action="advance"`, so both the
create redirect and pin clicks (`Turbo.visit(url, { frame })`) update the URL. The map container is
`data-turbo-permanent` so Leaflet survives Turbo visits and back/forward.

**Tech Stack:** Rails 8.1.4, Turbo, Stimulus, importmap, Leaflet 1.9.4, Tailwind, Minitest + Capybara.

**Spec:** [`docs/superpowers/specs/2026-11-09-wolfchatter-design.md`](../superpowers/specs/2026-11-09-wolfchatter-design.md) ·
PRD: [`docs/prd.md`](../prd.md) (FR-1, FR-2, FR-3; data model; real-time design) ·
Carry-forward: [`00-overview.md`](00-overview.md#carry-forward-notes-for-later-phase-plans) (phase 2 items)

## Global Constraints

- PRD data model for `chatrooms`, verbatim: `latitude` / `longitude` `decimal(10,6)`, not null,
  validated -90..90 / -180..180; `place_name` string, nullable. Title rule: `place_name.presence || "Chatroom #{id}"`.
- Panel copy: empty state "Click on the map to start a chat" (exists). Room panel shows the title.
- OpenStreetMap tiles `https://tile.openstreetmap.org/{z}/{x}/{y}.png`, attribution
  `© OpenStreetMap contributors` linked to `https://www.openstreetmap.org/copyright`, kept visible.
- Initial view: center `[48.0, 15.0]`, zoom `5` (Europe, as in the mockups).
- Pins never travel as JSON: initial and live pins are marker elements (CLAUDE.md).
- Hotwire only; no new JS dependencies besides Leaflet. Delete the stock `hello_controller.js`.
- No messages, names, broadcasts or geocoding in this phase (phases 3–4).
- Prosopite stays on; every test green; `bin/rubocop` and `bin/brakeman` clean.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Branch `phase-2-map-and-rooms`.

## Review Focus

- **Wrapped longitudes.** Leaflet lets you click a world copy with `lng` > 180. The map controller sends `latlng.wrap()` coordinates, and the server rejects out-of-range values with 422 (tests in Tasks 1 and 2).
- **Double-click creating two rooms.** Leaflet fires `click` twice on a double-click. `doubleClickZoom` is disabled, so zoom stays on the +/− controls and the scroll wheel (system test in Task 4: a double-click creates exactly 1 room).
- **Duplicate pins.** The current room's marker is rendered both in `#markers` and inside the panel. The map controller dedupes by room id (system test in Task 3: N rooms give N `.leaflet-marker-icon`).
- **Back/forward and deep links.** `/chatrooms/:id` loads directly with the room open. Back returns to the previous room or the empty state without breaking the map (system test in Task 4).
- **Unknown room id.** `GET /chatrooms/999999` returns 404 instead of an error page with a stack trace (integration test in Task 2).

---

### Task 1: Chatroom model

**Files:**
- Create: `db/migrate/<ts>_create_chatrooms.rb`, `app/models/chatroom.rb`
- Test: `test/models/chatroom_test.rb`, `test/fixtures/chatrooms.yml`

**Interfaces:**
- Produces: `Chatroom` with `latitude`, `longitude`, `place_name`; `Chatroom#title -> String`.
  Fixtures `chatrooms(:cluj)` (46.770439, 23.591423, place_name nil) and `chatrooms(:rome)`
  (41.902782, 12.496366, place_name "Rome, Italy").

- [ ] **Step 1: Write failing tests**

```ruby
require "test_helper"

class ChatroomTest < ActiveSupport::TestCase
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
end
```

- [ ] **Step 2:** `bin/rails test test/models/chatroom_test.rb` → FAIL (uninitialized constant Chatroom).
- [ ] **Step 3:** Migration `create_table :chatrooms` with `decimal :latitude, precision: 10, scale: 6, null: false`,
  same for `longitude`, `string :place_name`, timestamps. Model: presence + `numericality` range validations; `title` per the rule.
- [ ] **Step 4:** `bin/rails db:migrate && bin/rails test` → PASS; `bin/rubocop` clean.
- [ ] **Step 5: Commit** — `feat: add Chatroom model with coordinate validation and title`

### Task 2: Routes, controller, panel and marker partials

**Files:**
- Modify: `config/routes.rb`, `app/controllers/chatrooms_controller.rb`, `app/views/chatrooms/index.html.erb`
- Create: `app/views/chatrooms/show.html.erb`, `app/views/chatrooms/_map_page.html.erb`,
  `app/views/chatrooms/_panel.html.erb`, `app/views/chatrooms/_marker.html.erb`
- Test: `test/controllers/chatrooms_controller_test.rb` (extend)

**Interfaces:**
- Consumes: `Chatroom#title`, fixtures from Task 1.
- Produces:
  - routes `resources :chatrooms, only: %i[index show create]`, plus `root "chatrooms#index"`
  - `_map_page` (locals `chatrooms:`, `chatroom:` may be nil). It renders:
    - `<div id="map_container" data-turbo-permanent>` holding `#map`, `#markers` (one `_marker` per room) and the hidden create form `#new_chatroom_form` (`form_with url: chatrooms_path, data: { turbo_frame: "chatroom_panel" }`, with hidden `chatroom[latitude]` and `chatroom[longitude]`)
    - outside the container, `<turbo-frame id="chatroom_panel" data-turbo-action="advance">` holding `_panel` or `_empty_panel`
  - `_marker` (local `chatroom`): `<div id="<%= dom_id(chatroom, :marker) %>" data-controller="marker"` with values `data-marker-id-value`, `-lat-value`, `-lng-value`, `-title-value`, `-url-value` (`chatroom_path`)
  - `_panel` (local `chatroom`): `<h2 id="<%= dom_id(chatroom, :title) %>">` containing the title, plus a `_marker` for this room
  - `index` and `show` both render `_map_page`. The `show` action, when `turbo_frame_request?`, renders only the frame with `_panel` and skips the all-rooms query.
  - `create`: on success, `redirect_to chatroom, status: :see_other`. On invalid input, render the frame with the error messages, `status: :unprocessable_content`.

- [ ] **Step 1: Write failing tests** (add to the existing controller test):

```ruby
test "index renders a marker per room" do
  get root_path
  assert_select "#markers [data-controller=marker]", count: Chatroom.count
  assert_select "##{dom_id(chatrooms(:rome), :marker)}[data-marker-title-value=?]", "Rome, Italy"
end

test "create with valid coordinates redirects to the room" do
  assert_difference "Chatroom.count", 1 do
    post chatrooms_path, params: { chatroom: { latitude: 45.5, longitude: 10.25 } }
  end
  assert_redirected_to chatroom_path(Chatroom.last)
  assert_response :see_other
end

test "create rejects out-of-range coordinates" do
  assert_no_difference "Chatroom.count" do
    post chatrooms_path, params: { chatroom: { latitude: 10, longitude: 200 } }
  end
  assert_response :unprocessable_content
end

test "show renders the full page with the room open" do
  get chatroom_path(chatrooms(:cluj))
  assert_response :success
  assert_select "#map"
  assert_select "turbo-frame#chatroom_panel h2##{dom_id(chatrooms(:cluj), :title)}", "Chatroom #{chatrooms(:cluj).id}"
end

test "show as a frame request renders only the panel" do
  get chatroom_path(chatrooms(:rome)), headers: { "Turbo-Frame" => "chatroom_panel" }
  assert_select "turbo-frame#chatroom_panel h2", "Rome, Italy"
  assert_select "#markers", count: 0
end

test "show for an unknown room is not found" do
  get chatroom_path(id: 999_999)
  assert_response :not_found
end
```

Keep the existing "root shows the empty panel" test passing. `#markers` may stay `hidden`.

- [ ] **Step 2:** Run the controller test → FAIL.
- [ ] **Step 3:** Implement per Interfaces. `chatroom_params` = `params.expect(chatroom: %i[latitude longitude])`.
  Index orders rooms by `id`.
- [ ] **Step 4:** `bin/rails test` → PASS. `bin/rubocop` and `bin/brakeman` clean.
- [ ] **Step 5: Commit** — `feat: add chatroom routes, panel and marker partials`

### Task 3: Leaflet map with pins, CSP enabled

**Files:**
- Modify: `config/importmap.rb` (pin `leaflet` via `bin/importmap pin leaflet@1.9.4`, vendored), `config/initializers/content_security_policy.rb`, `app/views/chatrooms/_map_page.html.erb`
- Create:
  - `app/javascript/controllers/map_controller.js` and `app/javascript/controllers/marker_controller.js`
  - `app/assets/stylesheets/leaflet.css`: Leaflet 1.9.4's `dist/leaflet.css`, vendored with its license header
  - `app/assets/images/leaflet/marker-icon.png`, `marker-icon-2x.png` and `marker-shadow.png`, from Leaflet 1.9.4
- Delete: `app/javascript/controllers/hello_controller.js`
- Test: `test/system/map_page_test.rb` (extend)

**Interfaces:**
- Consumes: `_map_page` and `_marker` from Task 2.
- Produces:
  - `marker` controller. Its values are `id` (Number), `lat`, `lng` (Number), `title` and `url` (String). On `connect` it calls `this.dispatch("connect", { target: window, detail: { id, lat, lng, title, url } })`. Event name: `marker:connect`.
  - `map` controller, on `#map_container`.
    - Values: `tileUrl`, `attribution`, `center` (Array), `zoom` (Number), `iconUrl`, `iconRetinaUrl`, `shadowUrl`. The icon values are set with `image_path` so Propshaft digests them.
    - Targets: `map`, `form`, `latitude`, `longitude`.
    - Action: `marker:connect@window->map#register`.
    - Builds Leaflet on the `map` target with `doubleClickZoom: false`.
    - Keeps a `Map` from room id to Leaflet marker.
    - `register(event)` ignores ids it already knows. Each marker gets a tooltip with the title. On click it calls `Turbo.visit(url, { frame: "chatroom_panel", action: "advance" })`.
    - On `connect` it also registers any marker elements already in the DOM, whatever the controller connect order.
  - `#map` gets `role="region"` and `aria-label="Chat map"`.
  - CSP:
    - `default-src 'self'`
    - `img-src 'self' data: https://tile.openstreetmap.org`
    - `script-src 'self'` with nonce
    - `style-src 'self'` with nonce
    - `connect-src 'self'`
    - `object-src 'none'`, `base-uri 'self'`, `frame-ancestors 'none'`
    - nonce generator `->(_request) { SecureRandom.base64(16) }`, nonce directives `script-src style-src`

- [ ] **Step 1: Write failing system tests** (`ApplicationSystemTestCase`):

```ruby
test "existing rooms appear as pins without duplicates" do
  visit root_path
  assert_selector ".leaflet-marker-icon", count: Chatroom.count
end

test "opening a room by URL shows its pin once and its title" do
  visit chatroom_path(chatrooms(:rome))
  assert_selector "turbo-frame#chatroom_panel h2", text: "Rome, Italy"
  assert_selector ".leaflet-marker-icon", count: Chatroom.count
end

test "map shows OpenStreetMap attribution" do
  visit root_path
  assert_selector ".leaflet-control-attribution", text: "OpenStreetMap contributors"
end

test "page loads without Content Security Policy violations" do
  visit root_path
  assert_selector ".leaflet-marker-icon", count: Chatroom.count
  csp_errors = page.driver.browser.logs.get(:browser).select { _1.message.include?("Content Security Policy") }
  assert_empty csp_errors.map(&:message)
end
```

Tile requests go to the network. Only CSP messages are asserted, so tests stay green offline.
If `logs.get(:browser)` is unavailable on this Selenium version, enable the `goog:loggingPrefs`
browser log capability in `ApplicationSystemTestCase`.

- [ ] **Step 2:** `bin/rails test:system` → FAIL (no Leaflet markers).
- [ ] **Step 3:** Implement per Interfaces. Import Leaflet as an ES module from the pinned vendor file. Set the icon URLs through `L.Icon.Default.mergeOptions`, or with an explicit `L.icon`.
- [ ] **Step 4:** `bin/rails test && bin/rails test:system` → PASS. `bin/rubocop` and `bin/brakeman` clean.
  Run `bin/dev` and check by hand: tiles render, and the pins look like the mockup's blue teardrop. Note this in the report.
- [ ] **Step 5: Commit** — `feat: render Leaflet map with room pins and enable CSP`

### Task 4: Click to create, pin to switch, URL follows

**Files:**
- Modify: `app/javascript/controllers/map_controller.js`
- Test: `test/system/rooms_test.rb`

**Interfaces:**
- Consumes: the `map` controller (Task 3) and the `create` and `show` actions (Task 2).
- Produces: `map#create(event)`, bound to Leaflet's `click`. It writes `event.latlng.wrap()` lat/lng,
  rounded to 6 decimals, into the hidden inputs, then calls `form.requestSubmit()`.

- [ ] **Step 1: Write failing system tests**

```ruby
require "application_system_test_case"

class RoomsTest < ApplicationSystemTestCase
  test "clicking the map creates a room, drops a pin and opens it" do
    visit root_path
    assert_difference -> { Chatroom.count }, 1 do
      find("#map").click(x: 200, y: 200)
      assert_selector "turbo-frame#chatroom_panel h2", text: /Chatroom \d+/
    end
    assert_current_path chatroom_path(Chatroom.last)
    assert_selector ".leaflet-marker-icon", count: Chatroom.count
  end

  test "clicking a pin switches the panel and the URL" do
    visit chatroom_path(chatrooms(:cluj))
    find(".leaflet-marker-icon[title='Rome, Italy']").click
    assert_selector "turbo-frame#chatroom_panel h2", text: "Rome, Italy"
    assert_current_path chatroom_path(chatrooms(:rome))
  end

  test "back returns to the previous room" do
    visit chatroom_path(chatrooms(:cluj))
    find(".leaflet-marker-icon[title='Rome, Italy']").click
    assert_selector "turbo-frame#chatroom_panel h2", text: "Rome, Italy"
    page.go_back
    assert_selector "turbo-frame#chatroom_panel h2", text: "Chatroom #{chatrooms(:cluj).id}"
    assert_selector ".leaflet-marker-icon", count: Chatroom.count
  end

  test "double-clicking the map creates exactly one room" do
    visit root_path
    assert_difference -> { Chatroom.count }, 1 do
      find("#map").double_click(x: 250, y: 250)
      assert_selector "turbo-frame#chatroom_panel h2", text: /Chatroom \d+/
    end
  end
end
```

The pin selector uses Leaflet's `title` marker option. Set it to the room title in `register`, which also gives the pin an accessible name.
Clicks land at offsets that miss the fixture pins at the initial view. If one collides, move the offset.

- [ ] **Step 2:** `bin/rails test:system` → FAIL.
- [ ] **Step 3:** Implement `create`. If the double-click test shows two rooms even with `doubleClickZoom: false`, ignore the second click when it comes within 300 ms of the previous one, and record that in the report.
- [ ] **Step 4:** Run the full suite, rubocop and brakeman → green.
- [ ] **Step 5: Commit** — `feat: create rooms by clicking the map and switch rooms via pins`

### Task 5: README, PR

- [ ] **Step 1:** Add a short "Using Wolfchatter" section to README.md: click the map to open a room, and click a pin to switch rooms. Start an "Improvements over the mockups" section with two items: a URL per room, and OSM tiles.
- [ ] **Step 2: Commit** — `docs: describe map usage in README`
- [ ] **Step 3:** Push `phase-2-map-and-rooms` and open the PR with `gh`, linking this plan and listing the verification output.
- [ ] **Step 4: CHECKPOINT:** the lead engineer reviews the PR before merge.
