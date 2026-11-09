# Wolfchatter — Delivery Plan (Overview)

**Spec:** [`docs/superpowers/specs/2026-11-09-wolfchatter-design.md`](../superpowers/specs/2026-11-09-wolfchatter-design.md)
**Target date:** Tue 10 Nov 2026

Each phase gets its own detailed plan (`docs/plans/phase-N-*.md`), written just before the phase
starts so it reflects what earlier phases actually produced. A phase plan is approved by the lead
developer before execution. Execution: superpowers `subagent-driven-development` — one subagent
per task, review gate between tasks, TDD, small single-purpose commits.

## Git workflow

- `main` holds only merged, working states.
- One branch per phase (`phase-N-<slug>`), one pull request per phase, opened with `gh`.
  The PR description links the phase plan and summarises decisions taken during the phase.
- PRs are merged with a merge commit (no squash) so the task-by-task history stays readable.

## Phases

| # | Phase | Delivers | Exit criteria |
|---|---|---|---|
| 0 | Docs | `docs/prd.md` (1–2 pages), `CLAUDE.md` | PRD signed off by the lead developer |
| 1 | Skeleton | Rails 8.1 app on Postgres, Tailwind, test + lint + security tooling, README, empty-state page | `bin/rails test`, `bin/rails test:system`, `bin/rubocop`, `bin/brakeman` all green |
| 2 | Map & rooms | Leaflet/OSM map, click-to-create room, click pin to switch panel, URL per room | System test: create two rooms, switch between them, title changes |
| 3 | Messages | Name cookie, posting messages, real-time messages + new pins via Turbo Streams | System test: two browser sessions see each other's messages and pins live; N+1 proof test covers both an integration test and a system test |
| 4 | Place names | Nominatim reverse-geocoding job, live title update, fallback title | Job tests with stubbed HTTP (found / not found / failure) |
| 5 | Infra doc | `docs/infrastructure.md`: fly.io staging + production table with assumptions | Doc reviewed by lead developer |
| 6 | Self-review | `bin/review`, review agents + `/self-review` skill, `docs/review/report.md`, `docs/review/notes.md` | Lead developer has triaged every finding; fixes merged |
| 7 | README polish | Final `README.md` as the project's front page (see below) | Lead developer reads it top to bottom; a fresh clone runs by following it alone |

## README (built up across phases, finished in phase 7)

Phase 1 writes the setup/run/test core; each later phase appends what it changed. Phase 7 makes it
the front page: one-paragraph pitch + screenshot or short GIF of two browsers chatting live;
features; quick start (≤ 5 commands); architecture at a glance (request → Turbo Stream →
Action Cable flow, data model, geocoding job) with links to the PRD; key decisions and trade-offs;
improvements over the mockups; known limitations / not done; how the project was built with AI
(CLAUDE.md, plans, subagent-driven execution, self-review) with links; docs index.

## Cut order (if time runs short)

1. Live geocoded-title update (phase 4) → title is computed on next render instead.
2. Live pin fan-out to other browsers (phase 3) → pins appear on reload.
3. Geocoding entirely (phase 4) → `Chatroom <id>` titles only.

Each cut is recorded in the README and PRD as "documented, not done". Phases 6 and 7 are never cut.

## Human checkpoints

- Approve each phase plan before execution.
- Sign off the PRD (phase 0).
- Review each phase PR before merge.
- Triage every self-review finding (phase 6); `notes.md` records the lead developer's reasoning.
