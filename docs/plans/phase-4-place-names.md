# Phase 4 — Place Names Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** New rooms get a human place name such as "Cluj-Napoca, Romania" from OpenStreetMap's
Nominatim. The panel title and the pin title update live. If no place is found, or the lookup fails,
the room keeps `Chatroom <id>`.

**Architecture:**
- A small `ReverseGeocoder` PORO owns the HTTP call and the response parsing.
- A `GeocodeChatroomJob` orchestrates the lookup. Creating a chatroom enqueues it.
- The job is throttled globally with Solid Queue `limits_concurrency to: 1, key: "nominatim"` plus a
  1-second pause after each call. This stays within Nominatim's limit of 1 request per second.
- When `place_name` changes, the chatroom broadcasts two replaces:
  - the panel title, on the room stream;
  - its marker element, on `chatrooms`.
- The map controller then updates an existing pin's title instead of ignoring the repeated room id.

**Tech Stack:** Rails 8.1.4, Active Job + Solid Queue, Net::HTTP, Turbo Streams, WebMock (test only).

**Spec:** [`docs/superpowers/specs/2026-11-09-wolfchatter-design.md`](../superpowers/specs/2026-11-09-wolfchatter-design.md) ·
PRD: [`docs/prd.md`](../prd.md) (FR-4; Geocoding row) ·
Carry-forward: [`00-overview.md`](00-overview.md#carry-forward-notes-for-later-phase-plans) (phase 4 items: stale pin titles, `place_name` cap)

## Global Constraints

- PRD FR-4, verbatim: "The title is `Chatroom <id>` immediately; a background job reverse-geocodes the
  coordinates and, if a place is found, the title updates live (e.g. "Cluj-Napoca, Romania"). If
  nothing is found or the call fails, the fallback title stays."
- PRD Geocoding row: Nominatim reverse API, called server-side from the job, with an identifying
  User-Agent and timeouts. Use `limits_concurrency to: 1, key: "nominatim"` and wait about 1 s after
  each call. Failures are logged, and the fallback title stays.
- Endpoint: `https://nominatim.openstreetmap.org/reverse` with these params:
  `format=jsonv2`, `lat`, `lon`, `zoom=10`, `addressdetails=1`.
  Send the header `Accept-Language: en`.
  Set the User-Agent from `Rails.configuration.x.nominatim.user_agent`, defaulting to
  `Wolfchatter/1.0 (+https://github.com/ihoka/wolfchatter)`.
- Timeouts: `open_timeout` 2 s, `read_timeout` 3 s.
- Throttle pause: `Rails.configuration.x.nominatim.throttle` (seconds). Use `1.0` by default and `0`
  in the test environment.
- `place_name` is capped at 120 characters, truncated with "…".
- Tests never touch the network. Configure WebMock with `disable_net_connect!(allow_localhost: true)`.
  Allow localhost so system tests, Selenium and Capybara's server keep working.
- Broadcasts stay synchronous `broadcast_*_to` (CLAUDE.md).
- Prosopite stays on. Keep every test green and `bin/rubocop` and `bin/brakeman` clean.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Branch `phase-4-place-names`.

## Review Focus

- **Nominatim answers `{"error": "Unable to geocode"}` (open sea).** Expect a nil place name and the title unchanged (Task 1).
- **Timeout, DNS failure, HTTP 5xx or invalid JSON.** Expect nil, a warning in the log, no exception escaping the job, and no retry storm (Tasks 1 and 2).
- **Very long place names, or names containing markup.** Expect truncation to 120 characters, with the markup rendered escaped in the panel title and the pin tooltip (Tasks 1 and 3).
- **The job runs twice for the same room, for example after a retry.** It must not call the API again if `place_name` is already set (Task 2).
- **Another viewer has the room's pin before the name arrives.** Their pin title and tooltip must update to the place name (Task 3).

---

### Task 1: ReverseGeocoder

**Files:**
- Create: `app/models/reverse_geocoder.rb`, `config/initializers/nominatim.rb`, `test/models/reverse_geocoder_test.rb`
- Modify: `Gemfile` (test group: `webmock`), `test/test_helper.rb` (`require "webmock/minitest"`; `WebMock.disable_net_connect!(allow_localhost: true)`), `config/environments/test.rb` (`config.x.nominatim.throttle = 0`)

**Interfaces:**
- Produces:
  - `ReverseGeocoder.new.place_name(latitude, longitude) -> String | nil`
  - `ReverseGeocoder::MAX_LENGTH = 120`
  - `ReverseGeocoder::ENDPOINT = "https://nominatim.openstreetmap.org/reverse"`
  - Formatting: take the first present of `address.city`, `address.town`, `address.village`,
    `address.municipality`, `address.county`, `address.state`. Join it to `address.country` with
    ", ", using whichever parts are present. Otherwise use `display_name`. Otherwise return nil.
  - It rescues `Net::OpenTimeout`, `Net::ReadTimeout`, `SocketError`, `SystemCallError`,
    `OpenSSL::SSL::SSLError` and `JSON::ParserError`, logs a warning, and returns nil. A non-2xx
    response also logs and returns nil.

- [ ] **Step 1: Write failing tests**

```ruby
require "test_helper"

class ReverseGeocoderTest < ActiveSupport::TestCase
  def stub_nominatim(body:, status: 200)
    stub_request(:get, %r{\Ahttps://nominatim\.openstreetmap\.org/reverse})
      .to_return(status:, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  test "formats city and country and sends an identifying user agent" do
    stub_nominatim(body: { address: { city: "Cluj-Napoca", country: "Romania" }, display_name: "x" })
    assert_equal "Cluj-Napoca, Romania", ReverseGeocoder.new.place_name(46.77, 23.59)
    assert_requested :get, %r{reverse\?.*lat=46\.77.*lon=23\.59}, headers: { "User-Agent" => /Wolfchatter/ }
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

  test "truncates very long names to 120 characters" do
    stub_nominatim(body: { address: {}, display_name: "a" * 300 })
    assert_equal 120, ReverseGeocoder.new.place_name(1, 1).length
  end
end
```

- [ ] **Step 2:** `bundle install && bin/rails test test/models/reverse_geocoder_test.rb` → FAIL.
- [ ] **Step 3:** Implement with `Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 2, read_timeout: 3)`.
  Put the config defaults in the initializer under `Rails.application.config.x.nominatim`.
- [ ] **Step 4:** Run the full suite, rubocop and brakeman, and confirm all are green. Check that system tests still pass with WebMock loaded.
- [ ] **Step 5: Commit:** `feat: add Nominatim reverse geocoder`

### Task 2: GeocodeChatroomJob, enqueued on create

**Files:**
- Create: `app/jobs/geocode_chatroom_job.rb`, `test/jobs/geocode_chatroom_job_test.rb`
- Modify: `app/models/chatroom.rb`. `after_create_commit` also enqueues
  `GeocodeChatroomJob.perform_later(self)`. Add `validates :place_name, length: { maximum: ReverseGeocoder::MAX_LENGTH }, allow_nil: true`.

**Interfaces:**
- Consumes: `ReverseGeocoder#place_name` (Task 1).
- Produces:
  - `GeocodeChatroomJob#perform(chatroom)`. It skips if `place_name` is present. Otherwise it calls the
    geocoder, updates `place_name` when the result is non-nil, and always sleeps
    `Rails.configuration.x.nominatim.throttle` after a real call (`ensure`).
  - It declares `limits_concurrency to: 1, key: "nominatim", duration: 1.minute`. It does no retries,
    because the geocoder never raises for expected failures.

- [ ] **Step 1: Write failing tests**

```ruby
require "test_helper"

class GeocodeChatroomJobTest < ActiveJob::TestCase
  test "stores the place name" do
    stub_request(:get, /nominatim/).to_return(body: { address: { city: "Rome", country: "Italy" } }.to_json)
    room = chatrooms(:cluj)
    GeocodeChatroomJob.perform_now(room)
    assert_equal "Rome, Italy", room.reload.place_name
  end

  test "keeps the fallback title when nothing is found" do
    stub_request(:get, /nominatim/).to_return(body: { error: "Unable to geocode" }.to_json)
    room = chatrooms(:cluj)
    GeocodeChatroomJob.perform_now(room)
    assert_nil room.reload.place_name
    assert_equal "Chatroom #{room.id}", room.title
  end

  test "does not call the API when a place name exists" do
    GeocodeChatroomJob.perform_now(chatrooms(:rome))
    assert_not_requested :get, /nominatim/
  end

  test "place names longer than 120 characters are invalid" do
    assert_not chatrooms(:cluj).tap { _1.place_name = "a" * 121 }.valid?
  end

  test "creating a room enqueues the job" do
    assert_enqueued_with(job: GeocodeChatroomJob) { Chatroom.create!(latitude: 1, longitude: 2) }
  end
end
```

- [ ] **Step 2:** Run the tests and confirm they FAIL.
- [ ] **Step 3:** Implement per Interfaces. `limits_concurrency` is Solid Queue's Active Job extension. Confirm it loads in the test environment (`:test` adapter) without error.
- [ ] **Step 4:** Run the full suite, rubocop and brakeman, and confirm all are green.
  Check by hand in development: run `bin/dev`, click the map once on land, and watch `log/development.log` for the job and the title change. Note the result in the report.
- [ ] **Step 5: Commit:** `feat: geocode new rooms in a throttled background job`

### Task 3: Live title and pin updates

**Files:**
- Create: `app/views/chatrooms/_title.html.erb` (`<h2 id="<%= dom_id(chatroom, :title) %>" ...>` extracted from `_panel`)
- Modify: `app/views/chatrooms/_panel.html.erb`, `app/models/chatroom.rb`, `app/javascript/controllers/map_controller.js`
- Test: `test/models/chatroom_test.rb`, `test/system/place_names_test.rb`

**Interfaces:**
- Produces:
  - In `Chatroom`, an `after_update_commit` that runs `if: :saved_change_to_place_name?`. It does
    `broadcast_replace_to self, target: dom_id(self, :title), partial: "chatrooms/title"` and
    `broadcast_replace_to "chatrooms", target: dom_id(self, :marker), partial: "chatrooms/marker"`.
    Use `ActionView::RecordIdentifier.dom_id` in the model.
  - In `map_controller`, `add`/`register` updates the existing pin when a known room id arrives with a
    different title. It sets the marker icon's `title` and `alt` attributes, and calls
    `setTooltipContent` with a text node. It still never creates a duplicate pin.

- [ ] **Step 1: Write failing tests**

```ruby
# ChatroomTest
test "a new place name broadcasts the title and the marker" do
  room = chatrooms(:cluj)
  assert_turbo_stream_broadcasts(room, count: 1) do
    assert_turbo_stream_broadcasts("chatrooms", count: 1) { room.update!(place_name: "Cluj-Napoca, Romania") }
  end
end

# test/system/place_names_test.rb
require "application_system_test_case"

class PlaceNamesTest < ApplicationSystemTestCase
  test "title and pin update live when the place name arrives" do
    room = chatrooms(:cluj)
    using_session(:watcher) do
      visit chatroom_path(room)
      assert_selector "turbo-cable-stream-source[connected]", count: 2, visible: :all
    end
    room.update!(place_name: "Cluj-Napoca, <b>Romania</b>")
    using_session(:watcher) do
      assert_selector "turbo-frame#chatroom_panel h2", text: "Cluj-Napoca, <b>Romania</b>"
      assert_selector ".leaflet-marker-icon[title='Cluj-Napoca, <b>Romania</b>']"
      assert_selector ".leaflet-marker-icon", count: Chatroom.count
    end
  end
end
```

- [ ] **Step 2:** Run the tests and confirm they FAIL.
- [ ] **Step 3:** Implement per Interfaces.
- [ ] **Step 4:** Run the full suite, rubocop and brakeman, and confirm all are green. Run `place_names_test.rb` 3 times.
- [ ] **Step 5: Commit:** `feat: update room titles and pins live when the place name arrives`

### Task 4: Docs and PR

- [ ] **Step 1:** README:
  - Add "place names" to "Using Wolfchatter" and to "Improvements over the mockups".
  - Add Nominatim attribution and its usage-policy note: the request is identified with a User-Agent and throttled to 1 request per second.
- [ ] **Step 2: Commit:** `docs: describe place names`
- [ ] **Step 3:** Push `phase-4-place-names` and open the PR with `gh`.
