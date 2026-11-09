# Wolfchatter — Technical PRD

Wolfchatter is a real-time chat app on a map. Clicking anywhere on the map drops a pin, and that pin is a chatroom anyone can join. New messages, pins and titles appear live for everyone watching.

## Functional requirements

1. **FR-1 Empty state.** The map loads and shows the pins in view, grouped into count clusters when the view is dense (see [Viewport pins](#viewport-pins)); the panel reads "Click on the map to start a chat".
2. **FR-2 Create room.** Clicking empty map space immediately creates a chatroom at that lat/lng with no confirm step; a pin appears and the panel switches to the new room.
3. **FR-3 Switch room.** Clicking a pin switches the panel to that room's title and messages, and the URL follows (`/chatrooms/:id`) so deep links, refresh and back/forward work.
4. **FR-4 Room title.** The title is `Chatroom <id>` immediately; a background job reverse-geocodes the coordinates and, if a place is found, the title updates live (e.g. "Cluj-Napoca, Romania"). If nothing is found or the call fails, the fallback title stays.
5. **FR-5 Name once.** The user enters a display name once; it is stored in a cookie and reused (whitespace and zero-width characters stripped, required, max 40 characters, always rendered escaped), and the panel shows "Chatting as <name> (change)".
6. **FR-6 Messages.** Each message shows author name, body and timestamp, ordered oldest to newest, with the panel scrolled to the newest. Bodies have whitespace and zero-width characters stripped, blank ones are rejected, and they are capped at 1000 characters; ties in timestamp order by id.
7. **FR-7 Persistence.** Rooms and messages persist in PostgreSQL across sessions and restarts.
8. **FR-8 Real time.** New messages appear live for everyone viewing that room, new pins appear live for everyone viewing the map where they fall in view (in a clustered view they raise the count of their cluster), and geocoded titles update live.

## Out of scope

- Accounts and authentication
- Editing or deleting rooms and messages
- Moderation
- Place names or animated splitting on clusters (clusters show counts only)
- Search
- Read receipts and typing indicators
- CI pipeline (tests run locally)
- Actual deployment

## Technical decisions

| Area | Decision | Why |
|---|---|---|
| Stack | Ruby 3.4.5, Rails 8.1.x, PostgreSQL | Rails 8 ships the Solid libraries used instead of Redis. |
| Front-end | Hotwire (Turbo Frames/Streams), Stimulus only where JS is unavoidable (Leaflet map, scroll-to-bottom, name form); importmap, no Node build; Tailwind via `tailwindcss-rails` | Hotwire covers navigation and live updates without an SPA; no build step. |
| Map | Leaflet with standard OpenStreetMap tiles, loaded via importmap; OpenStreetMap attribution stays visible per the tile usage policy | No API key needed; matches the mockup's Leaflet look. |
| Real-time delivery | Turbo Streams over Action Cable, backed by Solid Cable on Postgres | One database server (Postgres), no Redis to run. |
| Background jobs | Solid Queue on Postgres | No Redis; geocoding must not block the request. |
| Geocoding | Nominatim reverse API, called server-side from the job with an identifying User-Agent and timeouts | Free and keyless. The job uses Solid Queue `limits_concurrency to: 1, key: "nominatim"` and waits ~1s after each call, so at most 1 req/s globally; failures are logged; the fallback title stays. |
| State management | Server is the source of truth; the client holds only Leaflet map state and the selected room (in the URL); display name in a cookie | Fewer sync bugs; deep links for free. |
| Testing | Minitest (models, requests, jobs) plus system tests with headless Chromium; Nominatim stubbed; run locally only | Rails default; stubs keep tests offline and deterministic. |

## Data model

**`chatrooms`**

| Column | Type | Constraints |
|---|---|---|
| `id` | bigint | primary key |
| `latitude` | decimal(10,6) | not null; validated -90..90 |
| `longitude` | decimal(10,6) | not null; validated -180..180 |
| `place_name` | string | nullable |
| `created_at`, `updated_at` | datetime | not null |

**`messages`**

| Column | Type | Constraints |
|---|---|---|
| `id` | bigint | primary key |
| `chatroom_id` | bigint | not null; foreign key to `chatrooms` |
| `author_name` | string | not null; whitespace and zero-width characters stripped, max 40 |
| `body` | text | not null; whitespace and zero-width characters stripped, present, max 1000 |
| `created_at`, `updated_at` | datetime | not null |

Index: `messages(chatroom_id, created_at)` supports per-room listing ordered by `created_at`, then `id`, and covers the foreign key.

Title rule: `place_name.presence || "Chatroom #{id}"`.

## Viewport pins

The map page renders no pins. After load, and after every pan or zoom (`moveend`, debounced 250 ms, with any in-flight request aborted), the browser requests `GET /chatrooms/markers` with `south`, `west`, `north`, `east` and `zoom`. The reply is one Turbo Stream `update` of `#markers`; there is no JSON endpoint.

- **Pins or clusters is decided by count, not zoom.** If the box holds 300 rooms or fewer (`MapMarkers::PIN_LIMIT`), the reply is pins, so a small map looks the same at every zoom. Otherwise it is clusters: counts per cell of a global grid, where the cell edge is `360 / 2**zoom * (80 / 256)` degrees (`MapMarkers::CELL_PX` is 80). The grid is doubled until the box holds at most 300 cells, so a zoomed-out reply is always bounded.
- **Lone rooms:** a cell with one room is drawn as an ordinary pin, never as a "1" bubble.
- **Cost:** at most 3 queries per request, each bounded by 300 rows and served by the `(latitude, longitude)` index on `chatrooms`.
- **Bad input:** missing, non-numeric or non-finite parameters, a longitude outside -180..180, or a zoom outside 0..19 return 400 (latitudes are clamped to -90..90); a request that doesn't accept a Turbo Stream returns 406. Responses are `no-cache`.
- **Clicking a cluster** zooms in by 2 levels (capped at 19). It never creates a room.
- **Deep links:** a full load of `/chatrooms/:id` centres the map on that room at zoom 5, and the panel carries its own marker, so the room is always pinned.

## Real-time design

Two Turbo Stream families:

- **`chatrooms`** (global): every client viewing the map subscribes. Creating a room broadcasts an append of a small, invisible marker element into `#live_markers` (which keeps only the last 20 elements), carrying data attributes for room id, lat, lng, title and URL; a Stimulus controller on it hands it to the map controller on connect. In a pin view the map adds the pin only if it is inside the current bounds; in a clustered view it increments the cluster for that grid cell, or adds a lone pin if the cell is empty. The map keys markers by room id and ignores known ids, so the creator (who gets both their own response and the broadcast) sees no duplicate. Title updates replace the room's marker elements.
- **Per room** (`[chatroom]`, via `turbo_stream_from @chatroom`): subscribed while a room is open. A new message broadcasts an append of the message partial to the list; the geocoding job broadcasts a replace of the room title.

## Improvements over the mockups

- **OSM tiles** instead of watercolor: no API key.
- **Place-name titles** instead of "Chatroom 2" alone.
- **Name once**, and a **URL per room**.

## Risks & assumptions

- **Honor-system names.** Names are neither unique nor authenticated, so spoofable; accepted, as accounts are out of scope.
- **Accidental room creation.** One click creates a room with no confirm step, as in the mockup; accepted.
- **Nominatim 1 req/s policy.** Geocoding is serialized to 1 req/s; under heavy creation a backlog builds and titles arrive late.
- **Rate limits:** 10 rooms and 30 messages per minute per IP (Rails `rate_limit`, Solid Cache). Per-IP, so a distributed flood is slowed, not stopped.
- **Cluster counts can drift.** Live updates adjust counts locally, so a count can be off by one between fetches (for example a room counted twice, or the creator's own cluster not incremented). The next pan or zoom reloads the exact counts.
