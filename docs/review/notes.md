# Self-review triage notes

> **Draft — pending lead developer confirmation.** Recommendations below were drafted by the AI controller; each fix/no-fix decision is confirmed or changed by the lead developer before merge.

Source: [`report.md`](report.md) (commit `87ce01d`, 12 confirmed findings). Re-run after fixes: `bin/review` green (85 runs, 0 failures, 100% line coverage, 0 Brakeman warnings, 0 RuboCop offenses).

## Fixed

| Finding | Decision | Why | Commit |
|---|---|---|---|
| **S1 (+S3)** medium — no rate limit on room creation | Fix | This was the cheapest way to stop someone covering the map with junk rooms, and it also stops the place-name queue filling up. We use Rails 8's built-in `rate_limit` (10 rooms per minute per IP), and the panel tells the user why nothing happened. | `aacc67b` |
| **S2** medium — no rate limit on messages | Fix | Same reasoning as S1. The limit is 30 messages per minute per IP. The report suggested 20; 30 is generous for people and still stops flooding. The form shows a "slow down" message. | `aacc67b` |
| **S4** low — `config.hosts` unset in production | Fix | It's one line of config. `APP_HOSTS` sets the allowed hosts, and `/up` stays open for health checks. It's documented in `docs/infrastructure.md`. There's no test, because it's production-only config. | `aacc67b` |
| **T3** low — names and messages made only of zero-width characters | Fix | Invisible authors and empty-looking messages make the chat confusing, and the fix is small. `VisibleText.strip` removes whitespace and zero-width characters from both ends before validation. | `e8e9959` |
| **T4** medium — the Nominatim concurrency limit and `discard_on` are untested | Fix (tests) | The throttle is how we stay within Nominatim's usage policy, so a regression there must fail the build. The tests check the limit, the key, and the deleted-room discard. | `0c7110d` |
| **T6** medium — author-name escaping is untested, and the body test passes even when the post fails | Fix (tests) | XSS in chat is the obvious risk. The tests now check that the post succeeds and that both the name and the body are escaped. | `0c7110d` |
| **T7** low — FR-6 panel rendering is untested | Fix (tests) | The tests cover the timestamp format and the 100-message window. Scroll-to-newest is client-side behaviour, and the system tests exercise it only indirectly. | `0c7110d` |
| **T8** low — cookie flags aren't asserted | Fix (tests) | A test now checks that the cookie is `HttpOnly` and `SameSite=Lax`, so nobody can drop those flags silently. | `0c7110d` |
| **T9** low — 406/400 responses are untested | Partly fixed | A 400 for a missing `chatroom` key and a 422 for a non-numeric latitude are now tested. The 406 claim was a false positive that the verifier confirmed: Rails already returns 406 via `rescue_responses`. | `0c7110d`, `8d8fe1f` |
| **Q1** low — every page renders every pin | Fix | The PRD had accepted this, but it grows with every room, so we changed the design instead of waiting for it to hurt. The map page now renders no pins. The browser asks for the visible area, and the server returns pins when 300 or fewer rooms are in view and count clusters on a grid otherwise. We chose server-side clustering because a client plugin would still ship every pin. Measured with 10,000 rooms in the development database (median of 5 runs after a warm-up, through `ActionDispatch::Integration::Session`, so no network): `GET /` is 5,492 bytes in 1.5 ms (was 3.7 MB and about 220 ms); a world-view markers request (zoom 3) is 1,867 bytes in 7.6 ms; a Europe-wide request at zoom 5 is 26,125 bytes in about 11.5 ms (median; the first runs were slower, up to 24 ms, and the five runs were 24.0, 18.3, 11.5, 11.0 and 10.8 ms); a city-box request at zoom 12 is 653 bytes in 1.7 ms, but that box held almost no rooms, so it is not a worst case. The Q1 figures came from a separate measurement, so treat the comparison as an order of magnitude, not a precise ratio. Design: [viewport pins](../superpowers/specs/2026-11-09-viewport-pins-design.md). | `91f7fb0`, `aab9e91`, `d4bb4b8`, `59037e6`, `7ae7a82` |

## Not fixed

| Finding | Decision | Why |
|---|---|---|
| **T2** low — if enqueuing the place-name job fails when a room is created, the request returns 500 and the pin isn't broadcast | Don't fix | Solid Queue's database is on the same Postgres server as the app's data. If enqueuing fails, the insert that just succeeded would usually fail too, and a 500 is an honest response to that. Rescuing the error would hide an infrastructure failure. |
| **T5** low — the room's creator can miss the live title update, because their room stream subscribes after the panel loads | Defer | The job is picked up 0–1 s after enqueue (1 s polling) plus a Nominatim round-trip, so the creator's stream usually subscribes first. The pin title still updates through the global stream. Refreshing the panel title when the stream connects would close it. That's worth doing, but it isn't needed for launch. |

## What I'd do with more time

- Refresh the panel title when its stream connects (T5).
- Keep a moderation path: let an admin hide a room or message. Rate limiting slows abuse but can't undo it.
- Add a real Solid Queue integration test for the Nominatim throttle, so we aren't relying on reading the gem's source.
- On first deploy, check that `request.remote_ip` is the real client IP behind the Fly proxy. The per-IP rate limits depend on it.

## Review of the review

The verifier refuted one finding (T1) that had been repeated across three earlier phase reviews. It also missed one: the 406 half of T9, which the final whole-branch review caught. Layered review works, and no single layer is sufficient.
