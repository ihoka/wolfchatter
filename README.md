# Wolfchatter

Wolfchatter is a real-time chat app on a map. Click anywhere to drop a pin; each pin is a chatroom
anyone can join, and new messages and pins appear live for everyone watching.

Built on Rails 8.1, Hotwire, PostgreSQL, Solid Queue and Solid Cable (no Redis, no Node build).
This is a work in progress: only the map page with its empty chat panel exists so far.
The full requirements are in the [PRD](docs/prd.md).

## Requirements

- Ruby 3.4.5. The version is pinned in `.ruby-version`, which mise, rbenv and similar tools read.
- PostgreSQL running locally and reachable by your user.
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
