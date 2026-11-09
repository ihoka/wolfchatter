---
name: self-review
description: Runs Wolfchatter's three-layer code review (bin/review tools, three focused AI reviewers, then an adversarial verifier for each finding) and writes docs/review/report.md. Use when asked to "run the self-review", "review the codebase before submission", or to re-run the review after fixes.
---
# /self-review

You are the controller. You run the layers in order, pass the results between them, and write the report.
You do not review the code yourself, and you do not decide what gets fixed.

| Layer | What runs | Output |
|---|---|---|
| 1. Deterministic | `bin/review` | `tmp/review/{brakeman,bundler-audit,importmap-audit,rubocop,tests}.txt`, `coverage/` |
| 2. Reviewers | `review-queries`, `review-test-gaps`, `review-security` (`.claude/agents/`) | YAML findings |
| 3. Verification | `review-verifier`, one run per finding | CONFIRMED / REFUTED / UNCERTAIN |

## Steps

1. **Layer 1.** Run `bin/review` from the repo root (the full run takes a few minutes). Record its summary
   table and exit code. If system tests cannot run (no Chromium), re-run with `bin/review --skip-system`
   and say so in the report. A failing tool does not stop the review: the reviewers get the failure as input.
2. **Scope.** Record `git rev-parse --short HEAD`, today's date and `git ls-files app config db test | wc -l`.
   The scope is those files plus `docs/prd.md`.
3. **Layer 2: dispatch all three reviewers in parallel, in one message.** In a fresh session they are
   available as `subagent_type` `review-queries`, `review-test-gaps` and `review-security`. If they are not
   loaded, dispatch `general-purpose` agents whose prompt is the body of the matching `.claude/agents/*.md`
   file (everything after the frontmatter). The result is the same. Each prompt ends with:
   > Repo: <absolute path>, commit <sha>. Layer 1 exit <code>; outputs in tmp/review/*.txt and coverage/.
   > Scope: `git ls-files app config db test` plus docs/prd.md. Return your YAML findings and seeded lines.
4. **Merge.** Collect all findings. Findings with the same root cause become one finding that keeps the
   first id and lists every reviewer (for example `S2 (+T4)`), with the higher severity. Do not merge
   findings that only share a file. Keep each reviewer's seeded-concern lines.
5. **Layer 3: verify each finding.** Dispatch one `review-verifier` per merged finding, in parallel
   batches of up to 5 (or `general-purpose` with the body of `.claude/agents/review-verifier.md`). Pass the
   finding's YAML verbatim, plus the repo path and commit. Do not add your own opinion of the finding.
   If the verifier gives a `severity_adjustment`, apply it and record the original severity.
6. **Write `docs/review/report.md`** from the template below. CONFIRMED findings are listed in full.
   UNCERTAIN findings get one short entry each. REFUTED findings are counted, not listed, except refuted
   seeded concerns, which go under "Checked and clean". Every seeded concern must appear in the report
   exactly once.
7. **Hand off for triage.** The lead developer decides fix, don't fix or defer for each finding. You may
   draft `docs/review/notes.md`, starting with:
   `> **Draft — pending lead developer confirmation.** Recommendations below were drafted by the AI controller; each fix/no-fix decision is confirmed or changed by the lead developer before submission.`
   Stop there, and tell the developer the report and the draft are ready.

## Report template

````markdown
# Self-review report

- **Date:** YYYY-MM-DD · **Commit:** `<sha>` · **Scope:** <n> files (`git ls-files app config db test`) + `docs/prd.md`
- **Process:** `bin/review` → 3 focused reviewers (queries, test gaps, security) → 1 adversarial verifier per finding.
  Only verified findings are listed.

## Layer 1: deterministic tools

| Tool | Status | Key number |
|---|---|---|
| brakeman | pass | 0 warnings |
| bundler-audit | | |
| importmap-audit | | |
| rubocop | | |
| tests | | runs / failures / errors |
| coverage | | % line |

## Layers 2–3: AI review

**N raised · C confirmed · R refuted · U uncertain** (queries a/b/c, test gaps a/b/c, security a/b/c as raised/confirmed/refuted)

### Confirmed findings

Ordered critical → low.

#### S1 · high · `app/controllers/chatrooms_controller.rb:11`: <title>
- **Raised by:** review-security (+review-test-gaps as T3)
- **Failure scenario:** <concrete input → wrong outcome>
- **Suggested fix:** <fix>
- **Verifier:** <one-line note; "severity adjusted from X" if applied>

### Uncertain

- **Q2 · medium · `file:line`**: <title>. Unresolved: <what would settle it>.

### Checked and clean

- <Seeded concern>: refuted, <one-line reason with file:line>.
- SSRF via geocoding: refuted, `ReverseGeocoder::ENDPOINT` is a constant and lat/lng are validated numerics.

## Triage

Decisions are recorded in [`notes.md`](notes.md) by the lead developer.

## How to re-run

1. `bin/review` (or `bin/review --skip-system` for a quick pass). Raw output is in `tmp/review/`.
2. In Claude Code, run `/self-review`. The reviewers and the verifier are defined in `.claude/agents/`.
3. Compare against this report. Commit the new report alongside the fixes.
````
