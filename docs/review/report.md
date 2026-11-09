# Self-review report

- **Date:** 2026-11-09 · **Commit:** `87ce01d` · **Scope:** 99 files (`git ls-files app config db test`) + `docs/prd.md`
- **Process:** `bin/review` → 3 focused reviewers (queries, test gaps, security) → 1 adversarial verifier per finding.
  Only verified findings are listed.

## Layer 1: deterministic tools

| Tool | Status | Key number |
|---|---|---|
| brakeman | pass | 0 warnings |
| bundler-audit | pass | none |
| importmap-audit | pass | none |
| rubocop | pass | 0 offenses |
| tests | pass | 71 runs, 0 failures, 0 errors |
| coverage | pass | 100.0% line |

## Layers 2–3: AI review

**14 raised · 12 confirmed · 1 refuted · 0 uncertain** (queries 1/1/0, test gaps 9/8/1, security 4/4/0 as raised/confirmed/refuted)

S3 was merged into S1 (same root cause: no rate limit on room creation), so 13 findings went to verification. S3 counts as confirmed through S1.

### Confirmed findings

Ordered critical → low, then by id. No critical or high findings remain after verification.

#### S1 (+S3) · medium · `app/controllers/chatrooms_controller.rb:11`: Anonymous, unthrottled room creation permanently litters the shared map
- **Raised by:** review-security (S1 and S3, merged)
- **Failure scenario:** A script fetches `/` for a CSRF token, then POSTs random in-range coordinates to `/chatrooms` at about 50 per second. Each request inserts a row, broadcasts a pin to every viewer and enqueues a Nominatim job. After an hour (about 180k rooms) every full page renders all rooms and the map is unusable, with no admin path to clean up. The geocode queue (S3) is also serialized behind one semaphore, so a legitimate room created later waits hours for its place name.
- **Suggested fix:** `rate_limit to: 10, within: 1.minute, only: :create` in `ChatroomsController` (Solid Cache in production); optionally a global hourly cap, since a per-IP limit does not stop a distributed flood.
- **Verifier:** Confirmed. Severity adjusted from high, because the PRD accepts the risk and nothing is deployed yet. Damage is permanent because there is no delete path.

#### S2 · medium · `app/controllers/messages_controller.rb:6`: Unthrottled message creation lets one client flood a room
- **Raised by:** review-security
- **Failure scenario:** With a name cookie set, a script POSTs 1000-character messages to `/chatrooms/1/messages` at 100 per second. Every viewer receives 100 appends per second and the latest 100 messages are all spam, so the room is unusable and the table grows without limit.
- **Suggested fix:** `rate_limit to: 20, within: 1.minute, only: :create` in `MessagesController`.
- **Verifier:** Confirmed. The name cookie, the 1000-character cap and CSRF are all passed by loading the room page once. The PRD deferred rate limiting to this review.

#### T4 · medium · `app/jobs/geocode_chatroom_job.rb:6`: Nominatim concurrency limit and `discard_on` are never exercised
- **Raised by:** review-test-gaps
- **Failure scenario:** If `limits_concurrency` is removed or keyed per room, three worker threads hit Nominatim in parallel and break the 1 request per second policy (risking an IP block) while the suite stays green. If `discard_on` is removed, a job for a deleted room raises and retries noisily.
- **Suggested fix:** Assert `GeocodeChatroomJob.concurrency_limit == 1` and that two rooms share one `concurrency_key`. Add a test that a job for a destroyed room is discarded without calling Nominatim.
- **Verifier:** Confirmed. Nothing in `test/` reads the concurrency settings or deserializes a missing room. The test adapter never enforces the limit.

#### T6 · medium · `app/views/messages/_message.html.erb:3`: Message author name escaping is untested, and the body-escape test passes even when the post fails
- **Raised by:** review-test-gaps
- **Failure scenario:** If the partial changes to `raw message.author_name`, a name like `<img src=x onerror=...>` runs for every viewer of the room and the suite stays green. The existing body-escape test has no status or count assertion, so a 422 re-render also passes.
- **Suggested fix:** Add a controller test that sets the name to `<b>x</b>`, posts a message, asserts success and asserts the escaped text appears in the append stream. Add `assert_response :success` to the existing escape test.
- **Verifier:** Confirmed. The `&lt;b&gt;` match in the display-name test comes from the compose area, not from a message. Medium fits a gap in the FR-5 escaping guarantee.

#### Q1 · low · `app/controllers/chatrooms_controller.rb:3`: Every full map page loads and renders a marker for every chatroom
- **Raised by:** review-queries
- **Failure scenario:** Query count stays at one (no N+1), but bytes and render time grow linearly. At 10k rooms a full page is 3.7 MB raw (173 KB gzipped) and takes about 220 ms server time, plus 10k marker controllers in the browser. Fine up to roughly 2-3k rooms, noticeably slow beyond about 5k.
- **Suggested fix:** Accepted risk per the PRD. When needed, select only the marker columns and move pins to a viewport-bounded JSON endpoint with a limit, or add clustering.
- **Verifier:** Confirmed at low severity (no adjustment). The PRD lists unbounded pin loading as accepted. Revisit past about 3-5k rooms.

#### S4 · low · `config/environments/production.rb:64`: `config.hosts` is commented out, so the Host header is not validated in production
- **Raised by:** review-security
- **Failure scenario:** A request with `Host: evil.example` yields `Location: https://evil.example/chatrooms/N`. This is exploitable only if a cache or proxy keyed without Host sits in front, and none is configured, so it is defence in depth.
- **Suggested fix:** Set `config.hosts` to the deployed domain(s) and exclude `/up` from host authorization.
- **Verifier:** Confirmed, low. The repo names no production domain yet, so there is nothing to put in the list today.

#### T2 · low · `app/models/chatroom.rb:6`: Enqueue failure on room create returns 500 and skips the pin broadcast
- **Raised by:** review-test-gaps
- **Failure scenario:** If the queue database is unavailable when a room is created, the row commits, the creator gets a 500, other viewers get no pin and the room is never geocoded. Solid Queue raises `SolidQueue::Job::EnqueueError`, which ActiveJob does not rescue.
- **Suggested fix:** Add a model test that stubs `perform_later` to raise and still expects one marker broadcast, plus a controller test expecting `:see_other`. The code also needs a change (rescue and log the enqueue error, or broadcast in an `ensure`), because tests alone will not pass.
- **Verifier:** Confirmed. Severity adjusted from medium: the queue database shares a server and credentials with the primary one, so failing alone is rare.

#### T3 · low · `app/models/display_name.rb:10`: Zero-width-space-only display names and message bodies pass validation
- **Raised by:** review-test-gaps
- **Failure scenario:** A name or body of `"​"` is accepted. The panel shows "Chatting as " with an invisible author, or a blank-looking message is posted, although FR-6 says blank is rejected.
- **Suggested fix:** Strip zero-width characters before validating `DisplayName` and `Message`, then add tests for invisible-only names and bodies.
- **Verifier:** Confirmed. Severity adjusted from medium. The fix is a model change plus tests, not tests alone.

#### T5 · low · `app/views/chatrooms/_panel.html.erb:13`: Creator's own live title update is untested, and the subscribe race is unpinned
- **Raised by:** review-test-gaps
- **Failure scenario:** After a map click, a fast Nominatim reply commits before the creator's panel subscribes. The creator keeps "Chatroom 42" while other viewers see the real place name.
- **Suggested fix:** Add a system test that updates the new room's `place_name` before waiting for the cable connection and expects the panel title to change. It will fail today and pin the need to re-fetch the title on connect.
- **Verifier:** Confirmed. The window is small. The race is argued from code, not reproduced in a browser.

#### T7 · low · `app/views/chatrooms/_panel.html.erb:4`: FR-6 panel rendering is untested (scroll to newest, timestamp, 100-message window)
- **Raised by:** review-test-gaps
- **Failure scenario:** If the scroll controller is detached, the `recent_messages` default limit changes, or the timestamp leaves the partial, the panel opens at the oldest message, loads every message or loses its time, and all tests stay green.
- **Suggested fix:** Add a system test for scroll-to-newest with 30 messages, a controller assertion for `time[datetime]`, and a model test that 101 messages return 100.
- **Verifier:** Confirmed. Existing tests cover ordering and dom ids only. The scroll check may need a wait for timing.

#### T8 · low · `app/controllers/concerns/display_name_cookie.rb:16`: Display-name cookie HttpOnly flag is not asserted
- **Raised by:** review-test-gaps
- **Failure scenario:** If `httponly` is dropped in a refactor, the name cookie becomes readable from JavaScript and the suite stays green.
- **Suggested fix:** Assert the Set-Cookie header contains `httponly` and `samesite=lax` in the display-names controller test.
- **Verifier:** Confirmed. Impact is limited because the cookie is signed and holds only a display name.

#### T9 · low · `app/controllers/messages_controller.rb:40`: 406 for the no-name HTML post and 400 for a missing chatroom key are untested
- **Raised by:** review-test-gaps
- **Failure scenario:** If `format.any` is removed from `render_name_form`, an HTML post without a name raises `UnknownFormat` or renders the wrong template, and the suite stays green. A missing `chatroom` key (400) and a non-numeric latitude (422) are also unpinned.
- **Suggested fix:** Add tests for an HTML message post without a name (406), a `chatrooms` POST without the `chatroom` key (400) and a non-numeric latitude (422).
- **Verifier:** Confirmed, narrower than raised. The `DisplayNames#destroy` 406 shares `render_compose` with `update`, which is already tested.

### Uncertain

None.

### Checked and clean

- Synchronous broadcast returning 500 (T1): refuted, `app/models/message.rb:6` does broadcast synchronously, but a Solid Cable outage cannot reach `save`. solid_cable 4.1.0 only queues the broadcast (`BatchedBroadcaster#broadcast`); a background `solid_cable_writer` thread does the insert and its `flush` rescues `StandardError` and reports it through `Rails.error`. Posting still returns 200 and the failure is logged. Only partial-render errors and a shutdown-time `Stopped` can still raise, and neither is the claimed scenario.
- NBSP-only names: refuted, `DisplayName.new(name: "  ")` is invalid because `blank?` matches `[[:space:]]` (`app/models/display_name.rb:9-13`). Only zero-width spaces get through, which is covered by T3.
- SSRF via geocoding: refuted, `ReverseGeocoder::ENDPOINT` is a constant (`app/models/reverse_geocoder.rb:9`) and lat/lng are validated numerics (`app/models/chatroom.rb:20-23`).
- Second job sharing the Nominatim concurrency group: no finding today. Solid Queue builds the key as `[concurrency_group, key]` with the group defaulting to the class name, and only `GeocodeChatroomJob` calls `ReverseGeocoder` (`app/jobs/geocode_chatroom_job.rb:14`). A future second Nominatim job would need an explicit shared `group:`.

## Triage

Decisions are recorded in [`notes.md`](notes.md) by the lead developer.

## How to re-run

1. `bin/review` (or `bin/review --skip-system` for a quick pass). Raw output is in `tmp/review/`.
2. In Claude Code, run `/self-review`. The reviewers and the verifier are defined in `.claude/agents/`.
3. Compare against this report. Commit the new report alongside the fixes.
