# Wolfchatter

Real-time chat rooms pinned on a map. Users drop a room on the map; everyone sees pins and messages live.

- Product requirements: [docs/prd.md](docs/prd.md)
- Design spec: [docs/superpowers/specs/2026-11-09-wolfchatter-design.md](docs/superpowers/specs/2026-11-09-wolfchatter-design.md)
- Delivery plans: [docs/plans/](docs/plans/) (start at `00-overview.md`)

## Stack

Ruby 3.4.5, Rails 8.1, PostgreSQL, Hotwire (Turbo + Stimulus), importmap, Tailwind,
Leaflet + OSM, Solid Queue, Solid Cable.
No Redis, no Node build, no SPA framework. Do not add any.

## Commands

Available once the Rails app is generated (phase 1).

- `bin/setup` / `bin/dev` (http://localhost:3000)
- `bin/rails test` / `bin/rails test:system`
- `COVERAGE=1 bin/rails test` writes `coverage/`
- `bin/rubocop`, `bin/brakeman`, `bin/bundler-audit`

## Conventions

- Hotwire first: server-rendered HTML + Turbo Streams. Stimulus only for behaviour HTML cannot
  express (map, scroll, form niceties). One Stimulus controller per behaviour.
- Thin controllers. Logic lives in models or small POROs under `app/models`. Jobs only orchestrate.
- Declare broadcasts in models: synchronous `broadcast_*_to` in `after_create_commit` is the
  default. It's a cheap Solid Cable insert, needs no job process, and system tests see it.
  Broadcasts render from partials shared with the normal views, using only record attributes.
- Live map pins: initial and live pins are both rendered as marker elements (data attributes) in
  `#markers`; no JSON endpoint or JSON blob, no client-side store. A Stimulus controller manages
  them, deduped by room id.
- Validate at the model: display name stripped, required, max 40; message body max 1000.
  Limits are defined in the PRD; change them there first.
- Strong params everywhere. Never render user input with `html_safe` or `raw`.
- External HTTP only inside jobs, always with timeouts. Nominatim calls run only in a
  concurrency-limited job. Stub all HTTP in tests; no live network in tests.

## Workflow

- TDD: write the failing test, watch it fail, then implement.
- Every N+1 is a bug: fix the query (includes/preload/counter cache); never disable, allowlist or rescue Prosopite to get green.
- Verify before claiming done: run the relevant commands above and quote the result.
- Small commits with Conventional Commit prefixes: `feat:`, `fix:`, `test:`, `docs:`, `chore:`, `refactor:`.
- One branch and PR per phase. Plans in `docs/plans/` are the source of truth for task scope.
- Precedence: spec > PRD > phase plan > these conventions; if a plan contradicts a convention, stop and ask the lead developer.
- Write docs for teammates; record every decision with its reason.
