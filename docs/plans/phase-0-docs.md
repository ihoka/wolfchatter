# Phase 0 — Docs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce the technical PRD and the project's AI context file before any code exists.

**Architecture:** Documentation only. The PRD is a 1–2 page distillation of the design spec aimed at
a teammate or AI agent starting the project; `CLAUDE.md` is the standing rule set every agent session
loads.

**Tech Stack:** Markdown.

**Spec:** [`docs/superpowers/specs/2026-11-09-wolfchatter-design.md`](../superpowers/specs/2026-11-09-wolfchatter-design.md)

## Global Constraints

- PRD length: 1–2 printed pages (≈ 600–1000 words, tables count).
- Docs describe a regular product project: no mention of interviews, candidates, grading, or the
  originating company. Requirements come from "the product request"; the human is "the lead developer".
- Every technical decision in the PRD states its reason in one clause.
- Branch: `phase-0-docs`. One PR into `main`, merge commit.

## Review Focus

- PRD contradicting the spec (e.g. Redis, SPA, CI) — reviewer diffs PRD decisions against spec §4.
- PRD over length — reviewer runs `wc -w docs/prd.md` (must be ≤ 1000).
- `CLAUDE.md` rules that can't be followed yet (commands that don't exist until phase 1) — each
  command is marked as available from phase 1 or is phrased so it stays true.
- Interview framing leaking into docs — reviewer greps for `interview|candidate|grad|brief`.
- Missing non-goals — PRD lists every non-goal from spec §3.

---

### Task 1: Branch and commit the plans

**Files:**
- Add: `docs/plans/00-overview.md`, `docs/plans/phase-0-docs.md`, `docs/plans/phase-1-skeleton.md`

- [ ] **Step 1:** `git switch -c phase-0-docs`
- [ ] **Step 2: Commit**

```bash
git add docs/plans
git commit -m "docs: add delivery overview and phase 0–1 plans"
```

### Task 2: Draft the technical PRD

**Files:**
- Create: `docs/prd.md`

**Interfaces:**
- Produces: the canonical requirements/decisions doc that `CLAUDE.md` (Task 3) and README link to.

Required sections, in order (headings exactly):

1. `# Wolfchatter — Technical PRD` + one-paragraph product summary.
2. `## Functional requirements` — numbered FR-1 … FR-8 matching spec §3 items 1–8 (empty state,
   create room, switch room, room title + geocoding fallback, name once via cookie, messages with
   validation, persistence, real time). Each FR is one or two sentences, testable.
3. `## Out of scope` — the spec §3 non-goals list, one line each.
4. `## Technical decisions` — a table `Area | Decision | Why` with rows: Stack, Front-end,
   Map, Real-time delivery, Background jobs, Geocoding, State management, Testing.
5. `## Data model` — the two tables (`chatrooms`, `messages`) with columns, types, constraints,
   indexes; title rule `place_name.presence || "Chatroom #{id}"`.
6. `## Real-time design` — the stream names: `chatrooms` (global, new pins) and one per room
   (`[chatroom]` via `turbo_stream_from @chatroom`, new messages + title updates); what each
   broadcast renders.
7. `## Improvements over the mockups` — OSM tiles, place-name titles, name entered once, URL per room.
8. `## Risks & assumptions` — honor-system names (spoofable), accidental room creation,
   Nominatim 1 req/s policy, no rate limiting initially (revisited in self-review).

- [ ] **Step 1:** Write `docs/prd.md` with the sections above.
- [ ] **Step 2: Verify** — `wc -w docs/prd.md` ≤ 1000; `grep -inE 'interview|candidate|grad|brief' docs/prd.md` returns nothing.
- [ ] **Step 3: Commit** — `git commit -m "docs: add technical PRD (draft)"`
- [ ] **Step 4: CHECKPOINT — stop.** The lead developer edits and signs off the PRD. Apply their
  edits in a follow-up commit `docs: revise PRD after review`. Do not start Task 3 until sign-off.

### Task 3: Write CLAUDE.md

**Files:**
- Create: `CLAUDE.md`

**Interfaces:**
- Consumes: `docs/prd.md` (linked, not duplicated).

Content (keep under ~80 lines; terse, imperative):

- **Project:** one line + links to `docs/prd.md`, spec, `docs/plans/`.
- **Stack:** Ruby 3.4.5, Rails 8.1, PostgreSQL, Hotwire (Turbo + Stimulus), importmap, Tailwind,
  Leaflet + OSM, Solid Queue, Solid Cable. No Redis, no Node build, no SPA framework.
- **Commands:** `bin/setup`, `bin/dev`, `bin/rails test`, `bin/rails test:system`, `bin/rubocop`,
  `bin/brakeman` (all exist from phase 1).
- **Conventions:**
  - Hotwire first: server-rendered HTML + Turbo Streams; Stimulus only for behaviour HTML can't
    express (map, scroll, form niceties). One Stimulus controller per behaviour.
  - Thin controllers, logic in models or small POROs under `app/models`; jobs only orchestrate.
  - Broadcasts declared in models (`broadcasts_to` / explicit `broadcast_*_later` callbacks), rendered
    from partials shared with the normal views.
  - Strong params everywhere; never render user input with `html_safe`/`raw`.
  - External HTTP only inside jobs, always with timeouts; stubbed in tests (no live network in tests).
- **Workflow rules:**
  - TDD: failing test first, watch it fail, then implement.
  - Every N+1 is a bug (Prosopite raises in test from phase 1).
  - Verify before claiming done: run the commands above and quote the result.
  - Small commits, Conventional Commits prefixes (`feat:`, `fix:`, `test:`, `docs:`, `chore:`, `refactor:`).
  - One branch + PR per phase; plans in `docs/plans/` are the source of truth for task scope.
  - Docs describe a product project; record decisions with their reason.

- [ ] **Step 1:** Write `CLAUDE.md`.
- [ ] **Step 2: Verify** — every command listed is in the phase 1 plan's verification steps.
- [ ] **Step 3: Commit** — `git commit -m "docs: add CLAUDE.md project rules for AI agents"`

### Task 4: Open and merge the PR

- [ ] **Step 1:** `git push -u origin phase-0-docs`
- [ ] **Step 2:** `gh pr create --base main --title "Phase 0: PRD and AI project rules" --body <summary linking docs/plans/phase-0-docs.md>`
- [ ] **Step 3: CHECKPOINT** — lead developer reviews; then `gh pr merge --merge --delete-branch`
  and `git switch main && git pull`.
