# Wolfchatter — Technical PRD

Wolfchatter is a real-time chat app on a map. Clicking anywhere on the map drops a pin, and that pin is a chatroom anyone can join. Rooms and messages persist, the room title is the place name where available, and new messages, pins and titles appear live for everyone watching. Requirements come from the product request and its low-fidelity mockups; this document records what we build, what we deliberately do not, and why.

## Functional requirements

1. **FR-1 Empty state.** The map loads showing all existing pins; the panel reads "Click on the map to start a chat".
2. **FR-2 Create room.** Clicking empty map space immediately creates a chatroom at that lat/lng with no confirm step; a pin appears and the panel switches to the new room.
3. **FR-3 Switch room.** Clicking a pin switches the panel to that room's title and messages, and the URL follows (`/chatrooms/:id`) so deep links, refresh and back/forward work.
4. **FR-4 Room title.** The title is `Chatroom <id>` immediately; a background job reverse-geocodes the coordinates and, if a place is found, the title updates live (e.g. "Cluj-Napoca, Romania"). If nothing is found or the call fails, the fallback title stays.
5. **FR-5 Name once.** The user enters a display name once; it is stored in a cookie and reused, and the panel shows "Chatting as <name> (change)".
6. **FR-6 Messages.** Each message shows author name, body and timestamp, ordered oldest to newest, with the panel scrolled to the newest. Blank messages are rejected and a maximum length applies.
7. **FR-7 Persistence.** Rooms and messages persist in PostgreSQL across sessions and restarts.
8. **FR-8 Real time.** New messages appear live for everyone viewing that room, new pins appear live for everyone viewing the map, and geocoded titles update live. (Marked optional in the request; in scope.)

## Out of scope

- Accounts and authentication
- Editing or deleting rooms and messages
- Moderation
- Pin clustering
- Search
- Read receipts and typing indicators
- CI pipeline (tests run locally)
- Actual deployment

## Technical decisions

| Area | Decision | Why |
|---|---|---|
| Stack | Ruby 3.4.5, Rails 8.1.x, PostgreSQL | Already installed locally; Rails 8 ships the Solid libraries we use instead of Redis. |
| Front-end | Hotwire (Turbo Frames/Streams), Stimulus only where JS is unavoidable (Leaflet map, scroll-to-bottom, name form); importmap, no Node build; Tailwind via `tailwindcss-rails` | Hotwire covers panel navigation and live updates without an SPA; no build step keeps setup trivial. |
| Map | Leaflet with standard OpenStreetMap tiles, loaded via importmap | No API key needed; matches the mockup's Leaflet look. |
| Real-time delivery | Turbo Streams over Action Cable, backed by Solid Cable on Postgres | One datastore, no Redis to run. |
| Background jobs | Solid Queue on Postgres | Same reason; geocoding must not block the request. |
| Geocoding | Nominatim reverse API, called server-side from the job with an identifying User-Agent and timeouts | Free and keyless; server-side calls let us honor its 1 req/s policy and fail quietly. |
| State management | Server is the source of truth; the client holds only Leaflet map state and the selected room (in the URL); display name in a cookie | Fewer sync bugs, and deep links come for free. |
| Testing | Minitest (models, requests, jobs) plus system tests with headless Chromium; Nominatim stubbed; run locally only | Rails default, fast feedback; stubs keep tests deterministic and offline. |

## Data model

**`chatrooms`**

| Column | Type | Constraints |
|---|---|---|
| `id` | bigint | primary key |
| `latitude` | decimal | not null; validated -90..90 |
| `longitude` | decimal | not null; validated -180..180 |
| `place_name` | string | nullable |
| `created_at`, `updated_at` | datetime | not null |

**`messages`**

| Column | Type | Constraints |
|---|---|---|
| `id` | bigint | primary key |
| `chatroom_id` | bigint | not null; foreign key to `chatrooms` |
| `author_name` | string | not null |
| `body` | text | not null; present, max length validated |
| `created_at`, `updated_at` | datetime | not null |

Index: `messages(chatroom_id, created_at)` supports per-room chronological listing and covers the foreign key.

Title rule: `place_name.presence || "Chatroom #{id}"`.

## Real-time design

Two stream families, both Turbo Streams over Action Cable:

- **`chatrooms`** (global): every client viewing the map subscribes. Creating a room broadcasts an append that renders the new pin.
- **Per room** (`[chatroom]`, via `turbo_stream_from @chatroom`): subscribed while a room is open. A new message broadcasts an append of the message partial to the list; the geocoding job broadcasts a replace of the room title.

Server-side rendering of partials keeps one source of truth for markup; clients never build HTML themselves.

## Improvements over the mockups

- **OSM tiles** instead of watercolor, so no API key is needed.
- **Place-name titles** (e.g. "Cluj-Napoca, Romania") instead of "Chatroom 2" alone.
- **Name entered once** instead of a field per message.
- **URL per room**, so rooms can be shared, refreshed and navigated with back/forward.

## Risks & assumptions

- **Honor-system names.** Names are neither unique nor authenticated, so they can be spoofed; accepted, since accounts are out of scope.
- **Accidental room creation.** One click creates a room with no confirm step, as in the mockup; accepted and documented, and may litter the map with empty rooms.
- **Nominatim 1 req/s policy.** Geocoding runs in a background job with an identifying User-Agent and timeouts; heavy traffic could breach the policy or cause missing titles, which fall back gracefully.
- **No rate limiting initially.** Room and message creation are unthrottled; to be revisited in the self-review and either fixed or consciously deferred.
