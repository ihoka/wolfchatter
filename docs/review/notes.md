# Self-review triage notes

> **Draft — pending lead developer confirmation.** Recommendations below were drafted by the AI controller; each fix/no-fix decision is confirmed or changed by the lead developer before submission.

Source: [`report.md`](report.md) (commit `87ce01d`, 12 confirmed findings). Re-run after fixes: `bin/review` green (83 runs, 0 failures, 100% line coverage, 0 Brakeman warnings, 0 RuboCop offenses).

## Fixed

| Finding | Decision | Why | Commit |
|---|---|---|---|
| **S1 (+S3)** medium — no rate limit on room creation | Fix | This was the cheapest way to stop someone covering the map with junk rooms, and it also stops the place-name queue filling up. We use Rails 8's built-in `rate_limit` (10 rooms per minute per IP), and the panel tells the user why nothing happened. | `aacc67b` |
| **S2** medium — no rate limit on messages | Fix | Same reasoning as S1. The limit is 30 messages per minute per IP, which is generous for people and stops flooding. The form shows a "slow down" message. | `aacc67b` |
| **S4** low — `config.hosts` unset in production | Fix | It's one line of config. `APP_HOSTS` sets the allowed hosts, and `/up` stays open for health checks. It's documented in `docs/infrastructure.md`. There's no test, because it's production-only config. | `aacc67b` |
| **T3** low — names and messages made only of zero-width characters | Fix | Invisible authors and empty-looking messages make the chat confusing, and the fix is small. `VisibleText.strip` removes whitespace and zero-width characters from both ends before validation. | `e8e9959` |
| **T4** medium — the Nominatim concurrency limit and `discard_on` are untested | Fix (tests) | The throttle is how we stay within Nominatim's usage policy, so a regression there must fail the build. The tests check the limit, the key, and the deleted-room discard. | `0c7110d` |
| **T6** medium — author-name escaping is untested, and the body test passes even when the post fails | Fix (tests) | XSS in chat is the obvious risk. The tests now check that the post succeeds and that both the name and the body are escaped. | `0c7110d` |
| **T7** low — FR-6 panel rendering is untested | Fix (tests) | The tests cover the timestamp format and the 100-message window. Scroll-to-newest is client-side behaviour, and the system tests exercise it only indirectly. | `0c7110d` |
| **T8** low — cookie flags aren't asserted | Fix (tests) | A test now checks that the cookie is `HttpOnly` and `SameSite=Lax`, so nobody can drop those flags silently. | `0c7110d` |
| **T9** low — 406/400 responses are untested | Fix (tests) | This pins down the error responses for an HTML post with no name, and for a missing room id. | `0c7110d` |

## Not fixed

| Finding | Decision | Why |
|---|---|---|
| **T2** low — if enqueuing the place-name job fails when a room is created, the request returns 500 and the pin isn't broadcast | Don't fix | Solid Queue's database is on the same Postgres server as the app's data. If enqueuing fails, the insert that just succeeded would usually fail too, and a 500 is an honest response to that. Rescuing the error would hide an infrastructure failure. |
| **T5** low — the room's creator can miss the live title update, because their room stream subscribes after the panel loads | Defer | The window is under about 100 ms, set against the job's 1 s polling, and the pin title still updates through the global stream. Refreshing the panel title when the stream connects would close it. That's worth doing, but it isn't needed for launch. |
| **Q1** low — every page renders every pin | Defer | The PRD accepted this risk. Measured at 10k rooms it's one 25 ms query and 173 KB gzipped, which is fine at the scale we expect. The proper fix, viewport-bounded loading or clustering, is a design change. Rate limiting (S1) also slows down growth that comes from abuse. |

## What I'd do with more time

- Load pins for the visible area only, with clustering, so the map scales past a few thousand rooms (Q1).
- Refresh the panel title when its stream connects (T5).
- Keep a moderation path: let an admin hide a room or message. Rate limiting slows abuse but can't undo it.
- Add a real Solid Queue integration test for the Nominatim throttle, so we aren't relying on reading the gem's source.
