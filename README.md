# Wolfchatter

Wolfchatter is a real-time chat app on a map. Click anywhere to drop a pin; each pin is a chatroom
anyone can join, and new messages and pins appear live for everyone watching.

Built on Rails 8.1, Hotwire, PostgreSQL, Solid Queue and Solid Cable (no Redis, no Node build).
Rooms, messages, live updates and place names work.
The full requirements are in the [PRD](docs/prd.md).

## Using Wolfchatter

- **Open a room:** click anywhere on the map. A pin drops there and the panel on the right
  switches to the new room.
- **Switch rooms:** click any pin. The panel shows that room, and the URL changes to
  `/chatrooms/:id`, so links, refresh and back/forward all work.
- **Zoom:** use the +/− buttons or the scroll wheel. Double-click zoom is off, so a double-click
  can't create two rooms.
- **Chat:** enter your name once. It's remembered in a cookie, and you can change it at any time.
  Then type a message and press Submit.
- **Live:** new messages in the open room, and new pins anywhere on the map, appear for everyone
  without reloading.
- **Place names:** a new room starts as "Chatroom 12". A moment later it is renamed after the place
  you clicked, for example "Cluj-Napoca, Romania", for everyone watching. A room in the open sea
  keeps its number.

## Improvements over the mockups

- **Name entered once:** the mockups ask for your name with every message. Here you enter it once
  and it's remembered in a signed cookie.
- **Place-name titles:** rooms are named after their location instead of "Chatroom 1, 2, 3".
- **A URL per room:** each room has its own address, so rooms can be shared and bookmarked, and
  the browser's back button moves between them.
- **OpenStreetMap tiles** replace the watercolor tiles in the mockups. They need no API key, and
  the attribution stays visible.

Place names come from [Nominatim](https://nominatim.org/) (© OpenStreetMap contributors). Lookups
happen server-side in a background job. The job sends an identifying User-Agent and is throttled to
one request per second, as Nominatim's usage policy requires.

## Known limitations

- **Names work on the honor system.** There are no accounts, so anyone can pick any name.
- **History:** the panel shows the 100 most recent messages in a room.
- **Timestamps are shown in UTC.**
- **Every map click creates a room,** including stray ones. This matches the mockups.
- **Missed pins after a dropped connection:** pins created while your live connection was down
  show up only after a full reload, because the map keeps its pins across in-app navigation.
- **Very fast Back:** pressing Back within milliseconds of clicking a pin can leave the panel
  showing the room you just opened. The next navigation corrects it. This comes from how Turbo
  finishes a frame visit.

## Requirements

- Ruby 3.4.5. The version is pinned in `.ruby-version`, which mise, rbenv and similar tools read.
- PostgreSQL running locally and reachable by your user. `bin/setup` connects over the local socket
  as your OS user, which needs a PostgreSQL role with CREATEDB (`sudo -u postgres createuser --createdb $USER`),
  or set `DATABASE_URL` / `PGHOST` / `PGUSER`.
- Chrome or Chromium for system tests. Set `CHROME_BIN` to the browser binary if it is not
  found on your `PATH`.

## Setup

```sh
bin/setup
```

This installs gems and prepares the databases, then starts the app. `bin/setup` creates four
databases: development primary (`wolfchatter_development`), development queue and cable
(`wolfchatter_development_queue`, `wolfchatter_development_cable`), and `wolfchatter_test`.
Use `bin/setup --skip-server` to set up without starting the app.

## Run

```sh
bin/dev
```

Then open http://localhost:3000. `bin/dev` starts Puma with Solid Queue running inside it
(`SOLID_QUEUE_IN_PUMA=1`) plus the Tailwind watcher.

Note: a bare `bin/rails server` enqueues background jobs but does not run them, because Solid
Queue only runs inside Puma when `SOLID_QUEUE_IN_PUMA=1` is set. Use `bin/dev`.

## Test

```sh
bin/rails test           # unit and integration tests
bin/rails test:system    # headless-Chrome system tests
bin/rails test:all       # everything
```

Coverage is off by default. `COVERAGE=1 bin/rails test` writes a report to `coverage/` for unit
and integration tests, and `COVERAGE=1 bin/rails test:all` includes system tests. Prosopite runs
in the test environment and fails tests on N+1 queries.

## Quality

```sh
bin/rubocop
bin/brakeman
bin/bundler-audit
```

## Project docs

- [Product requirements (PRD)](docs/prd.md)
- [Design spec](docs/superpowers/specs/2026-11-09-wolfchatter-design.md)
- [Delivery plans](docs/plans/00-overview.md)
- [CLAUDE.md](CLAUDE.md): conventions and workflow for contributors and coding agents
