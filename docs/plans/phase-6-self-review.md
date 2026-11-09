# Phase 6 — Self-Review Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A repeatable, committed review setup that combines deterministic tools, focused AI
reviewers and an adversarial verification pass. We run it against the final code and commit both the
setup and its report. The lead developer then triages every finding (fix, or don't fix and why), and
the agreed fixes land.

**Architecture:** Three layers. One entry point.

| Layer | What runs | Why |
|---|---|---|
| 1. Deterministic | `bin/review`: Brakeman, bundler-audit, importmap audit, RuboCop, `COVERAGE=1 bin/rails test:all` (Prosopite raises on N+1) | Mechanical problems are caught by tools, not opinions; output is reproducible |
| 2. Focused AI reviewers | Three Claude Code agents in `.claude/agents/`: `review-queries`, `review-test-gaps`, `review-security` | One concern each — the team's recurring priorities (N+1 queries, missing edge-case tests, security); narrow prompts find more and hallucinate less |
| 3. Verification | `review-verifier` agent, one run per finding, instructed to *disprove* it against the code | Counters confident AI false positives; only CONFIRMED findings reach the report |

Entry point: the `/self-review` skill (`.claude/skills/self-review/SKILL.md`). It runs layer 1,
dispatches the layer 2 reviewers in parallel with the layer 1 output, sends each finding through layer
3, and writes `docs/review/report.md`.

**Spec:** [`docs/superpowers/specs/2026-11-09-wolfchatter-design.md`](../superpowers/specs/2026-11-09-wolfchatter-design.md) §6

## Global Constraints

- Every reviewer finding uses this format: `id`, `severity` (critical/high/medium/low), `file:line`,
  `title`, `evidence` (quoted code), `failure scenario` (concrete input → wrong outcome),
  `suggested fix`.
- The verifier returns `CONFIRMED`, `REFUTED` or `UNCERTAIN`, with its reasoning and the code it
  checked. Only CONFIRMED findings are listed as findings. UNCERTAIN findings appear in a separate
  short section. REFUTED findings are counted, not listed, to keep the report readable.
- Reviewer agents are read-only. Their tools are Read, Grep, Glob and Bash, with Bash used for
  running tests or tools only. They never edit files.
- **Seeded concerns.** The reviewers get the known candidates from earlier phase reviews, so the
  report considers them explicitly, and they must still look beyond them:
  - no rate limiting;
  - a synchronous broadcast failure after commit returns 500 for a message that was already saved;
  - zero-width or NBSP-only names;
  - unbounded pin load;
  - the room creator can miss the title broadcast, because their room stream subscribes after the
    frame loads;
  - an enqueue failure on create returns 500 and skips the pin broadcast;
  - spamming room creation fills the geocode queue;
  - concurrency and `discard_on` are not exercised under real Solid Queue;
  - a second job calling Nominatim would need the same concurrency group, not just the same key.

  Phase 4's final review checked SSRF via geocoding and found no path to it: the host is a
  constant and the params are numeric and validated. Record that as checked.
- **Triage belongs to the lead developer.** The controller drafts recommendations in
  `docs/review/notes.md`, marked **"Draft — pending lead developer confirmation"**. Recommended
  fixes are implemented, so the developer can veto them. A finding is resolved only when the
  developer confirms it at the end.
- Docs are written for the product team.
- Commits end with a Co-Authored-By trailer naming the model that wrote them.
- Branch: `phase-6-self-review`.

## Review Focus

- The agents and the skill must be usable in a fresh session, not only in this one: the paths in the
  skill and the agent names must match the files.
- `bin/review` must fail loudly: it exits non-zero if any tool fails, and prints a summary table.
- The report must make clear what each layer contributed, and how many findings verification
  refuted.

---

### Task 1: `bin/review` (layer 1)

**Files:** Create `bin/review` (Ruby or POSIX sh, executable). Output goes to `tmp/review/`, which is git-ignored via `/tmp`.

- [ ] It runs the following, each with output captured to `tmp/review/<tool>.txt`:
  - `bin/brakeman -q --no-pager`
  - `bin/bundler-audit`
  - `bin/importmap audit`
  - `bin/rubocop`
  - `COVERAGE=1 bin/rails test:all`
- [ ] It prints a summary table of tool, status and key number: warnings, offenses, failures and the coverage %, read from `coverage/.last_run.json`.
- [ ] It exits 1 if any tool failed.
- [ ] Verify it twice: once green, and once with a deliberate RuboCop offense in a scratch file. The second run must exit 1. Delete the scratch file afterwards.
- [ ] Commit: `chore: add bin/review for deterministic checks`

### Task 2: Reviewer agents and the `/self-review` skill (layers 2–3)

**Files:**
- Create:
  - `.claude/agents/review-queries.md`
  - `.claude/agents/review-test-gaps.md`
  - `.claude/agents/review-security.md`
  - `.claude/agents/review-verifier.md`
  - `.claude/skills/self-review/SKILL.md`

Each agent file has frontmatter (`name`, `description`, `tools`, `model`) and a body with:
- its single focus, plus an explicit "out of scope: other concerns";
- a checklist specific to this stack.

**Checklists:**
- **`review-queries`:**
  - N+1 in views, partials, broadcasts and jobs;
  - missing indexes for every `where` and `order`;
  - unbounded queries;
  - query count per page (use the logs in `tmp/review/test.txt` or `bin/rails runner` probes);
  - Prosopite blind spots, meaning code paths no test executes.
- **`review-test-gaps`:**
  - read the coverage report and every requirement in `docs/prd.md` (FR-1..8);
  - list each untested edge case with the test that would pin it, including invalid input, failure
    paths and concurrency or ordering;
  - flag tests that assert nothing meaningful.
- **`review-security`:**
  - Rails security guide items: XSS (ERB, Leaflet HTML sinks, broadcasts), CSRF, mass assignment,
    cookie flags, CSP, open redirects, SSRF via geocoding, Action Cable stream exposure, rate
    limiting and abuse, secrets and credentials, dependency CVEs (from layer 1), `force_ssl` and
    host authorization.
- **`review-verifier`:**
  - given one finding, tries to refute it by reading the cited code and the paths around it;
  - may run a focused test or probe in a scratch location outside the repo;
  - returns a verdict and the evidence for it.

**The skill** (`SKILL.md`) contains:
- when to use it;
- the steps:
  - run `bin/review`;
  - collect the scope (`git ls-files app config db test`, plus the PRD);
  - dispatch the three reviewers in parallel, each with the layer 1 output paths;
  - merge and de-duplicate their findings;
  - dispatch one verifier per finding, in parallel batches;
  - write `docs/review/report.md` using the template inside the skill.

**Report template:**
- header: date, commit, scope;
- layer 1 table;
- confirmed findings, ordered by severity;
- uncertain findings;
- a stats line ("N raised · C confirmed · R refuted · U uncertain");
- a "How to re-run" section.

The skill also notes: if a fresh session has not loaded the custom agents, dispatch general-purpose
subagents with the agent file's body as the prompt. The result is equivalent.

- [ ] Write the files.
- [ ] Validate each agent's frontmatter by eye against the Claude Code docs format.
- [ ] Commit: `feat: add AI review agents and /self-review skill`

### Task 3: Run the review, commit the report

- [ ] Execute the skill exactly as written. The controller follows `SKILL.md`, using the agent files' bodies as prompts.
- [ ] Write `docs/review/report.md`.
- [ ] Commit: `docs: add self-review report`

### Task 4: Triage, fix, note

- [ ] The controller drafts `docs/review/notes.md` with this header:
  `> **Draft — pending lead developer confirmation.** Recommendations below were drafted by the AI controller; each fix/no-fix decision is confirmed or changed by the lead developer before merge.`
- [ ] For each confirmed finding, the notes record:
  - the decision: fix / don't fix / defer;
  - one line of reasoning;
  - for fixes, the commit.
- [ ] Recommended fixes are implemented through the normal task loop: implementer, then reviewer. Each fix needs a test that fails before the fix.
- [ ] The notes end with a short "What I'd do with more time" section.
- [ ] Re-run `bin/review` after the fixes. It must be green.
- [ ] Commit: `docs: add review triage notes`
- [ ] PR: open and merge it after the final review.
