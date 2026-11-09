# Phase 5 — Infrastructure & Cost Estimate Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A short document, `docs/infrastructure.md`, that describes how Wolfchatter would be deployed
on fly.io for a **staging** and a **production** environment. It is a table of component → service →
why → estimated monthly cost, with explicit assumptions. Nothing is actually deployed.

**Architecture:** One Rails app image, the Dockerfile that `rails new` generated. It runs Puma with
Solid Queue inside it (`SOLID_QUEUE_IN_PUMA`), so jobs need no separate process at this scale. It
talks to one PostgreSQL cluster that holds the primary, queue, cable and cache databases. There is
no Redis. Tiles and geocoding are third-party: OpenStreetMap tiles and Nominatim.

**Spec:** [`docs/superpowers/specs/2026-11-09-wolfchatter-design.md`](../superpowers/specs/2026-11-09-wolfchatter-design.md) ·
Carry-forward: [`00-overview.md`](00-overview.md#carry-forward-notes-for-later-phase-plans) (phase 5 items)

## Global Constraints

- **Length:** about one page. Tables first, prose only for assumptions and decisions.
- **Environments:** staging and production, each with its own table and monthly total.
- **Costs:** monthly USD, stated as estimates. Name the pricing source and say when it was checked.
  Round to whole dollars. If a price cannot be verified, say so and give a range.
- **Carry-forward items to address:**
  - Production multi-database URLs. `DATABASE_URL` only feeds the primary database, so recommend
    one Postgres cluster with four databases and `QUEUE_/CABLE_/CACHE_DATABASE_URL` settings, or
    point all four at one database.
  - Host authorization (`config.hosts`).
  - The production cache database.
  - Cookie `Secure`, which `force_ssl` already covers. Mention it in one line.
- **Third-party usage policies:**
  - OSM tile usage policy: heavy use needs a commercial tile provider. State the threshold assumption
    and the alternative provider with its cost.
  - Nominatim usage policy: at most 1 request per second, an identifying User-Agent, and no bulk
    geocoding. State when to switch to a self-hosted or paid geocoder.
    - The throttle is a Solid Queue semaphore, one per database. Production and staging each have
      their own, but they send the same User-Agent. Recommend a separate User-Agent or contact per
      environment, set from an env var like `NOMINATIM_USER_AGENT`, or turning geocoding off in
      staging.
    - Several app machines sharing one Postgres still have one global throttle.
    - The ceiling is about 86k lookups a day, so titles start to lag past that. That point, or
      spam, is the trigger to switch to a paid or self-hosted geocoder.
    - Storing `place_name` per room satisfies Nominatim's request to cache results.
- **Docs are written for the product team.** Commits end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Branch: `phase-5-infrastructure`.

## Review Focus

- Every row has a cost and a reason. No "TBD".
- The totals add up.
- The assumptions are concrete: users, messages per day, rooms, storage, egress.
- Nothing contradicts the app's real configuration: Solid Queue in Puma, Solid Cable, `force_ssl`, and Dockerfile/Thruster.
- The secrets list is complete: `RAILS_MASTER_KEY` or `SECRET_KEY_BASE`, and the database URLs.

---

### Task 1: Write `docs/infrastructure.md`

**Files:** Create `docs/infrastructure.md`. Modify `README.md` to add one link in the docs index.

Sections, in this order:

1. **Assumptions.** A short list:
   - Staging is internal, with a handful of users.
   - Production is a modest public launch, for example around 1k daily users, around 20k messages
     per day, under 5 GB of database storage in year one, and about 10 GB of egress per month.
   - Region `otp` (Bucharest) or the nearest region, with the reason.
   - The date the prices were checked.
2. **Table: Production.** Columns are component | service chosen | why | est. monthly cost. Rows:
   - **App:** a Fly Machine, `shared-cpu-1x` with 1 GB RAM. Use 2 machines for zero-downtime deploys
     and redundancy, behind auto-stop disabled.
   - **Database:** Fly Managed Postgres, the smallest production plan, holding the four databases.
     Compare it with self-managed Postgres on a Fly volume and say why managed wins.
   - **Background jobs:** Solid Queue inside Puma, at $0. Note when to split it out into its own
     process group.
   - **WebSockets:** Solid Cable on the same Postgres, at $0. Fly's proxy supports WebSockets.
   - **TLS and the domain certificate:** Fly certs, included. Add a domain cost if you choose one.
   - **Outbound bandwidth:** estimate it from the assumptions.
   - **Map tiles:** OSM's public tiles cost $0 but are policy-limited. The upgrade path is a paid
     provider such as MapTiler, Stadia or Thunderforest. Give the price of the plan that fits.
   - **Geocoding:** Nominatim's public API costs $0 within its policy. The upgrade path is a paid
     provider or self-hosting, with its cost.
   - **Error tracking and logs:** Fly's log shipping, or a free tier (for example Sentry developer).
     State it as optional.
   - **Total.**
3. **Table: Staging.** The same columns:
   - 1 machine with auto-stop and auto-start, so it scales to zero.
   - The smallest development or unmanaged Postgres.
   - The same third-party services as production.
   - Total.
4. **Configuration notes:**
   - Secrets per environment: `RAILS_MASTER_KEY`, `DATABASE_URL`, `QUEUE_DATABASE_URL`,
     `CABLE_DATABASE_URL`, `CACHE_DATABASE_URL`.
   - `config.hosts` set to the app domain.
   - `SOLID_QUEUE_IN_PUMA=1`.
   - The release command `bin/rails db:prepare`.
   - The health check `/up`.
   - `force_ssl` makes cookies Secure.
5. **When this stops being enough.** Three bullets on what to change first as load grows:
   - split out a jobs process group;
   - move to a paid tile and geocoding provider;
   - scale Postgres up, then add read replicas.

- [ ] **Step 1:** Check the current fly.io pricing (Machines, Managed Postgres, bandwidth) and the
  tile and geocoder provider prices on the web. Record the sources and the date.
- [ ] **Step 2:** Write the document following the outline above.
- [ ] **Step 3: Verify.** Recompute both totals by hand. Grep the doc for "TBD". Cross-check the
  configuration notes against `config/database.yml`, `config/environments/production.rb`,
  `config/puma.rb` and the `Dockerfile`.
- [ ] **Step 4: Commit.** Message: `docs: add infrastructure and cost estimate for fly.io`.
- [ ] **Step 5:** Push, then open the PR with `gh`.
