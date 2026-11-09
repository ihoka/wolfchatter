# Wolfchatter — Design

Date: 2026-11-09 · Status: draft for approval · Target date: Tue 10 Nov 2026

## 1. Intent

Wolfchatter is a real-time chat app on a map: click anywhere on the map to drop a pin, and that pin
*is* a chatroom anyone can join.

Beyond the product itself, the project values a transparent engineering process:

- ambiguity in the requirements is resolved explicitly and documented,
- what gets built and — just as visibly — what deliberately does not,
- architecture decisions are recorded with their reasoning,
- the AI-assisted workflow is captured in committed artifacts (rules, plans, review setup).

Every non-obvious decision is **written down with its reason** — in the PRD, in the plans, or in
commit messages. A clean, deliberate git history is part of the deliverable.

## 2. Deliverables (all in one GitHub repo)

| Deliverable | Location |
|---|---|
| Source code + README (how to run locally, improvements over the original mockups) | repo root |
| Technical PRD, 1–2 pages, written **before** code | `docs/prd.md` |
| AI setup: rules, agents, skills | `CLAUDE.md`, `.claude/` |
| High-level plan + one detailed plan per phase | `docs/plans/` |
| Infrastructure & cost estimate (fly.io, staging + production) | `docs/infrastructure.md` |
| Review configuration | `.claude/` (skill + agents), `bin/review` |
| Review report + "what I fixed / didn't fix and why" note | `docs/review/report.md`, `docs/review/notes.md` |

This design doc (`docs/superpowers/specs/`) is the brainstorming output; the PRD is distilled from it.

## 3. Functional requirements

Mockups (low-fidelity wireframes from the product request): a browser window titled "Wolfchatter" showing a full-screen
Leaflet map of Europe (watercolor tiles, zoom +/- top-left, "Leaflet" attribution bottom-right) with a
white bordered panel floating top-right.
- Screen 1: panel contains only "Click on the map to start a chat".
- Screen 2: a blue teardrop pin where the user clicked; panel shows centered title "Chatroom 1",
  a scrollable message list (each item: `user_name:` + bold message text, date `01/02/2017`
  right-aligned beneath, divider line), then an input "write your user name here", then an input
  "write message here" with a "Submit" button beside it.
- Screen 3: second pin; title changes to "Chatroom 2".
- Screen 4: annotation — user inputs name and message and can submit.
Our deviations, all to be listed in the README as improvements: OSM tiles instead of watercolor
(no API key), place-name titles, name entered once instead of a field per message, URL per room.

1. **Empty state.** Map loads showing all existing pins. Panel reads "Click on the map to start a chat".
2. **Create a room.** Clicking empty map space immediately creates a chatroom at that lat/lng
   (no confirm step — matches the mockup; accidental rooms are an accepted, documented trade-off).
   A pin appears and the panel switches to the new room.
3. **Switch rooms.** Clicking an existing pin switches the panel to that room (title + messages).
   The URL follows the selected room (`/chatrooms/:id`) so deep links, refresh and back/forward work.
4. **Room title.** Shown immediately as `Chatroom <id>`. A background job reverse-geocodes the
   coordinates via **Nominatim** and, if a place is found, stores it and the title updates live
   (e.g. "Cluj-Napoca, Romania"). If nothing is found (open sea) or the call fails, the fallback
   title stays.
5. **Name.** The user enters a display name **once**; it is stored in a cookie and reused.
   The panel shows "Chatting as <name> (change)". Names are not unique, not authenticated —
   honor system, stated explicitly in the PRD.
6. **Messages.** Each message shows author name, body, timestamp. Ordered oldest→newest,
   panel scrolls to the newest. Blank messages are rejected; a reasonable max length applies.
7. **Persistence.** Rooms and messages persist in PostgreSQL across sessions/restarts.
8. **Real time (marked optional in the request — in scope).** New messages appear live
   for everyone viewing that room; new pins appear live for everyone viewing the map; geocoded
   titles update live.

### Non-goals (deliberately not built — listed in the PRD as such)

Accounts/authentication, editing or deleting rooms/messages, moderation, pin clustering, search,
read receipts/typing indicators, CI pipeline (tests run locally), actual deployment.

### Anti-goals (would make this a failure even if it "works")

- Gold-plating that buries the core product and the reasoning behind it.
- A heavy JS front-end (SPA) where Hotwire suffices.
- Undocumented decisions, or a messy, unexplained git history.
- AI review output committed without human triage.

## 4. Technical decisions (made up front)

- **Stack:** Ruby 3.4.5, Rails 8.1.x (installed locally), PostgreSQL (running locally).
- **Front-end:** Hotwire — Turbo Frames/Streams for panel navigation and updates, Stimulus only where
  JS is unavoidable (the Leaflet map controller, scroll-to-bottom, name form). Importmap, no Node build.
  Tailwind via `tailwindcss-rails`.
- **Map:** Leaflet with standard OpenStreetMap tiles (no API key). Leaflet loaded via importmap.
- **Real time:** Turbo Streams over Action Cable, backed by **Solid Cable** on Postgres (no Redis).
  Streams: one per chatroom (messages, title), one global (new pins).
- **Background jobs:** **Solid Queue** on Postgres (no Redis) for reverse geocoding. Solid Queue is the
  Active Job adapter in development as well as production, so `limits_concurrency` (Nominatim ≤ 1 req/s)
  holds wherever jobs really run; test uses the `:test` adapter.
- **Geocoding:** Nominatim reverse API, called server-side from the job with an identifying
  User-Agent and timeouts, respecting its 1 req/s usage policy.
- **State management:** server is the source of truth; the client holds only the Leaflet map state
  and the currently selected room (reflected in the URL). Display name lives in a cookie.
- **Data model (starting point):**
  - `chatrooms`: `latitude`, `longitude` (decimal, validated ranges), `place_name` (nullable),
    timestamps. Title = `place_name.presence || "Chatroom #{id}"`.
  - `messages`: `chatroom_id` (FK, indexed), `author_name`, `body`, timestamps;
    index supports per-room chronological listing.
- **Tests:** Minitest (models, controllers/requests, jobs) + system tests with headless Chromium.
  External HTTP (Nominatim) stubbed in tests. Run locally only.

## 5. AI workflow (how the work is executed)

1. Brainstorm → this design doc.
2. High-level plan with phases → `docs/plans/`.
3. Per phase: a detailed implementation plan (superpowers `writing-plans`), then execution with
   **subagent-driven development** (one subagent per task, review between tasks), TDD,
   small single-purpose commits.
4. `CLAUDE.md` captures project rules: stack and conventions, Hotwire-first, how to run tests/lint,
   TDD and "verify before claiming done", commit style.

### Phases

0. **Docs:** PRD + CLAUDE.md (PRD comes before any code).
1. **Skeleton:** Rails app, Postgres, test setup, RuboCop, Brakeman, README.
2. **Map & rooms:** Leaflet/OSM, click-to-create, pin-to-switch, URL follows room.
3. **Messages:** name cookie, posting, real-time messages and pins.
4. **Place names:** reverse-geocoding job, live title update.
5. **Infra doc:** fly.io staging + production cost table with stated assumptions.
6. **Self-review:** build the review setup, run it, fix, write report + note.
7. **README polish:** final `README.md` as the project's front page.

### Execution rules (decided)

- **Cut order under time pressure:** phases run in order so the repo is always shippable. If time is
  short, trim from the end of the app phases first (live title updates, then live pin fan-out, then
  geocoding entirely become "documented, not done" in the README/PRD). **Never cut the self-review
  (phase 6) or the README polish (phase 7)** — a full review of a smaller app beats a polished app
  with no review, and the README is the project's front page.
- **Human checkpoints — execution stops and waits for the lead developer at:**
  - approval of each phase's detailed plan before it executes;
  - the PRD: AI drafts, the developer edits and signs off;
  - review triage: the developer personally decides fix / don't-fix for each finding; `notes.md`
    records *their* reasoning (AI may transcribe, not decide).
- **Git history:** one branch + pull request per phase, merged into `main`. Each PR description links
  its phase plan. First commit on `main`: `.gitignore` (incl. `.mise.local.toml`, machine-local) and
  this design doc. Use the `gh` CLI for GitHub operations.

## 6. Self-review design

Focus areas (the team's recurring review priorities): **N+1 queries, missing edge-case tests, security.**

- **Layer 1 — deterministic tools** (one command, `bin/review`): Brakeman, bundler-audit, RuboCop,
  SimpleCov coverage, and **Prosopite** enabled in the test environment so N+1s fail the suite.
- **Layer 2 — focused AI reviewers** (committed Claude Code agents), one per concern:
  - *Queries/performance:* N+1s Prosopite can't see (views, broadcasts), missing indexes, unbounded queries.
  - *Test gaps:* reads coverage + code, lists untested edge cases (blank/oversized messages,
    invalid coordinates, missing name cookie, geocoder failure/timeout, broadcasts).
  - *Security:* cookie handling, XSS (messages, geocoded titles), mass assignment, CSRF on
    room creation, rate limiting, Action Cable stream exposure.
- **Layer 3 — verification:** each finding is handed to a separate agent that tries to *disprove*
  it against the code; only confirmed findings enter the report (counters AI false positives).
- **Entry point:** a `/self-review` skill orchestrating all three layers, so the review is repeatable.
- **Output:** `docs/review/report.md` (ranked findings) and `docs/review/notes.md`
  (fixed / not fixed / why — e.g. rate limiting or name spoofing may be consciously deferred).

## 7. Left to the builder

Visual styling details beyond the mockup layout; exact message max length; exact place-name
formatting from Nominatim's response; fly.io sizing assumptions and numbers; the precise split of
tasks inside each phase; agent prompt wording.
