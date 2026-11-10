# Wolfchatter — Technical PRD

Owner: Istvan Hoka, lead engineer · Status: approved; updated for viewport pins (phase 8)

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

## Open questions and how they were settled

| Open question | Decision | Why |
|---|---|---|
| Real time is optional | In scope: messages, new pins and titles are live | It's the core of a shared map chat, and Turbo Streams make it cheap. |
| "Stored between sessions": in the browser or on the server? | Server (PostgreSQL) | Rooms are shared, so everyone must see them. |
| The mockup asks for a name with every message | Name once, kept in a signed cookie, changeable | Less friction, with the same honor-system identity. |
| Does every map click create a room? | Yes, with no confirm step; double-click zoom is off | Matches the mockup. Stray rooms are an accepted risk. |
| Rooms are titled "Chatroom 2" | `Chatroom <id>` at once, then the place name from a background job | Meaningful names without slowing the click. |
| Accounts and moderation | Not built | Not requested. Rate limits slow abuse. |
| What happens with many rooms? | Load only the visible area; cluster dense areas on the server | The page stays small at any room count (added in phase 8). |

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
| Front-end | Hotwire (Turbo Frames/Streams), Stimulus only where JS is unavoidable (Leaflet map and its marker elements, scroll-to-bottom); importmap, no Node build; Tailwind via `tailwindcss-rails` | Hotwire covers navigation and live updates without an SPA; no build step. |
| Map | Leaflet with standard OpenStreetMap tiles, loaded via importmap; OpenStreetMap attribution stays visible per the tile usage policy | No API key needed; matches the mockup's Leaflet look. |
| Real-time delivery | Turbo Streams over Action Cable, backed by Solid Cable on Postgres | One database server (Postgres), no Redis to run. |
| Background jobs | Solid Queue on Postgres | No Redis; geocoding must not block the request. |
| Geocoding | Nominatim reverse API, called from a background job with an identifying User-Agent and timeouts | Free and keyless. `limits_concurrency to: 1` plus a ~1 s wait keeps us at 1 req/s globally; on failure the fallback title stays. |
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

Indexes: `messages(chatroom_id, created_at)` supports per-room listing ordered by `created_at`, then `id`, and covers the foreign key. `chatrooms(latitude, longitude)` serves the viewport query.

Title rule: `place_name.presence || "Chatroom #{id}"`.

## Viewport pins

The map page renders no pins. After load and after each pan or zoom (debounced 250 ms, stale requests aborted), the browser requests `GET /chatrooms/markers` with the bounding box and zoom, and the reply is one Turbo Stream `update` of `#markers`; there is still no JSON endpoint.

- **Pins or clusters, by count:** 300 rooms or fewer in view (`MapMarkers::PIN_LIMIT`) gives ordinary pins at any zoom; more gives count clusters on a global grid. A cell with one room is drawn as a pin. Clicking a cluster zooms in by 2 levels and never creates a room.
- **Bounded output:** at most 3 queries and at most 300 pins or clusters per reply. Bad parameters return 400; non-Turbo-Stream requests return 406.
- **Deep links:** a full load of `/chatrooms/:id` centres the map on that room, and the panel carries its own pin.

Details, including the grid formula and the live-update rules: [viewport pins design](superpowers/specs/2026-11-09-viewport-pins-design.md).

## Real-time design

Two Turbo Stream families:

- **`chatrooms`** (global): every map viewer subscribes. Creating a room appends a hidden marker element (room id, lat, lng, title, URL as data attributes) to `#live_markers`, which keeps the last 20. The map adds the pin if it is in view, or in a clustered view raises the count of its cell. Markers are keyed by room id, so the creator sees no duplicate. Title updates replace the room's marker elements.
- **Per room** (`[chatroom]`, via `turbo_stream_from @chatroom`): subscribed while a room is open. A new message broadcasts an append of the message partial to the list; the geocoding job broadcasts a replace of the room title.

## Risks & assumptions

- **Honor-system names.** Names are neither unique nor authenticated, so spoofable; accepted, as accounts are out of scope.
- **Accidental room creation.** One click creates a room with no confirm step, as in the mockup; accepted.
- **Nominatim 1 req/s policy.** Geocoding is serialized to 1 req/s; under heavy creation a backlog builds and titles arrive late.
- **Rate limits:** 10 rooms and 30 messages per minute per IP (Rails `rate_limit`, Solid Cache). Per-IP, so a distributed flood is slowed, not stopped.
- **Cluster query cost grows with the room count.** A zoomed-out markers request groups every room in view, and the endpoint has no rate limit. Accepted: 7.6 ms for a world view at 10,000 rooms. Past roughly 100,000 rooms, pre-aggregate the grid per zoom level.
- **Missed updates after a reconnect.** Nothing is replayed when the live connection returns: missed pins appear on the next pan, missed messages and titles on reload. Accepted for launch.
- **Cluster counts can drift** by one between fetches; the next pan or zoom reloads exact counts.
