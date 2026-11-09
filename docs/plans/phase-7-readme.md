# Phase 7: README Polish Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `README.md` into the project's front page. A newcomer should understand what Wolfchatter
is, see it, run it in five commands, grasp the architecture and the key decisions, and find every
project document, all from this one page.

**Spec:** [`docs/superpowers/specs/2026-11-09-wolfchatter-design.md`](../superpowers/specs/2026-11-09-wolfchatter-design.md) ·
Overview: [`00-overview.md`](00-overview.md) (README section)

## Global Constraints

- Sections, in this order:
  1. a one-paragraph pitch
  2. a screenshot
  3. features
  4. quick start (5 commands or fewer)
  5. architecture at a glance
  6. key decisions and trade-offs
  7. improvements over the mockups
  8. known limitations
  9. how this was built with AI
  10. docs index
- Keep the existing Requirements, Setup, Run, Test and Quality content. Fold it in under quick start
  plus a "Development" section. Do not lose any command or caveat:
  - `CHROME_BIN`
  - PostgreSQL role
  - bare `rails server`
  - coverage
  - `bin/review`
- Every claim must match the code and the docs. Link to the PRD, infrastructure doc, review report and
  notes, and plans rather than repeating them.
- Docs are written for the product team.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Branch `phase-7-readme`.

---

### Task 1: Screenshot

- [ ] Write a throwaway script, not committed, using Capybara with headless Chromium at 1400×900. It must:
  1. seed 3 rooms with place names, e.g. "Cluj-Napoca, Romania", "Rome, Italy", "Vienna, Austria";
  2. add a few messages in one room;
  3. open that room;
  4. save `docs/screenshot.png`.

  OSM tiles load from the network, so run it with network access.
- [ ] Check the image by viewing it: tiles, pins, panel with messages, the name line. Keep it under about 400 KB.
- [ ] Commit: `docs: add app screenshot`

### Task 2: Rewrite README

- [ ] **Architecture at a glance.** Use a small mermaid or ASCII diagram showing:
  - browser → Turbo frame / Stimulus (map, marker)
  - Rails controllers → Postgres
  - broadcasts → Solid Cable → `turbo_stream_from` (global `chatrooms` stream plus per-room streams)
  - `GeocodeChatroomJob` → Solid Queue (throttled) → Nominatim → title/pin replace

  Then give 4–6 bullets on the data model and the streams.
- [ ] **Key decisions.** A table with columns decision | why | trade-off. Rows:
  - Hotwire over SPA
  - pins as marker elements, not JSON
  - synchronous broadcasts
  - Solid Queue/Cable on Postgres with no Redis
  - signed-cookie name, honor system
  - per-session CSP nonce
  - throttled geocoding job
  - rate limits
- [ ] **How this was built with AI.** Cover:
  - brainstorm → design spec → PRD → phased plans
  - subagent-driven execution, with a fresh reviewer per task and a whole-branch review per phase
  - CLAUDE.md rules
  - the three-layer `/self-review`: tools → focused reviewers → adversarial verifier
  - one honest line on what the process caught. Examples:
    - the CSP nonce issue
    - the missing `require "net/http"` hidden by WebMock
    - the verifier refuting a finding repeated across three reviews

  Link to `CLAUDE.md`, `.claude/`, `docs/plans/` and `docs/review/`.
- [ ] **Docs index.** List the PRD, the spec, the plans, the infrastructure doc, the review report and notes, and `CLAUDE.md`.
- [ ] **Verify:**
  - every link resolves (`ls` each path);
  - every command in the README exists;
  - the quick start works from a clean database (`bin/rails db:drop && bin/setup --skip-server && bin/rails test`);
  - `grep -inE 'interview|candidate'` returns nothing.
- [ ] Commit: `docs: polish README as the project front page`
- [ ] Push, open the PR, and merge it after review.
