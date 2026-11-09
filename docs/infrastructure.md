# Infrastructure and cost estimate (fly.io)

How we would run Wolfchatter on fly.io for staging and production. Nothing is deployed yet; this is a plan and a budget.

## Assumptions

- **Staging:** internal use, a handful of users, idle most of the day.
- **Production:** a modest public launch: about 1k daily users, 20k messages per day, under 5 GB of database storage in year one, about 10 GB of egress per month.
- **Region: `fra` (Frankfurt).** The nearest region to Romania that offers Fly Managed Postgres. `otp` (Bucharest) is not in Fly's Managed Postgres region list, and the app and database should share a region for low latency.
- **Prices checked 2026-11-09** (see Sources). Machine prices below are the published `iad`/`ewr` rates; the `fra` rate was not confirmed and may differ slightly (unverified). Prices are USD per month.

## Production

| Component | Service | Why | Est. monthly cost |
|---|---|---|---|
| App | 2 Fly Machines, `shared-cpu-1x`, 1 GB, auto-stop off | Two machines give zero-downtime deploys and redundancy. 1 GB covers Rails with Solid Queue in Puma. 2 x $6.70 | $13.40 |
| Database | Fly Managed Postgres, Basic (shared-2x, 1 GB), one cluster holding four databases (primary, cache, queue, cable) | Backups, failover and upgrades are handled for us. Self-managed Postgres on a Fly volume would be about $10 (machine + volume) but we would own backups, restore drills and upgrades. 5 GB storage at $0.28/GB adds $1.40; plan $38.00 | $39.40 |
| Background jobs | Solid Queue inside Puma (`SOLID_QUEUE_IN_PUMA=1`) | Place-name lookups are one job per new room, throttled to 1/s. No extra process needed | $0 |
| WebSockets | Solid Cable on the same Postgres | No Redis. Fly's proxy supports WebSockets | $0 |
| TLS and certificate | Fly certs | The first 10 single-hostname certificates are free | $0 |
| Domain | Registrar of choice (about $12/year) | Needed for a custom hostname; estimate, not a Fly charge | $1.00 |
| Outbound bandwidth | Fly egress, Europe $0.02/GB, no free allowance | 10 GB x $0.02. Tiles come from the tile provider, not us. Shared IPv4 and IPv6 are free | $0.20 |
| Map tiles | OSM public tiles | Free but policy-limited (light use, attribution, no heavy use). Upgrade: MapTiler Flex $30/month for 500k requests (see Sources) | $0 |
| Geocoding | Nominatim public API | Free within policy (identifying User-Agent, 1 request/s), which our job already follows. Upgrade: LocationIQ Free (5,000 requests/day, 2/s) or Developer $100/month (25,000/day) | $0 |
| Error tracking and logs (optional) | `fly logs` plus a free tier such as Sentry Developer | Optional. Logs go to STDOUT already | $0 |
| **Total** | | 13.40 + 39.40 + 0 + 0 + 0 + 1.00 + 0.20 + 0 + 0 + 0 | **$54.00** |

With a paid tile provider the total is about $84 (+$30). Tile volume is the unknown: roughly 50 tiles per map load, 1k daily users could pass 500k requests per month, which would need a higher plan (unverified).

## Staging

| Component | Service | Why | Est. monthly cost |
|---|---|---|---|
| App | 1 Fly Machine, `shared-cpu-1x`, 1 GB, auto-stop and auto-start | Scales to zero when idle; billed per second while running. Assumes about 25% uptime ($6.70 x 0.25 = $1.68) plus stopped root filesystem storage (about $0.32) | $2.00 |
| Database | Unmanaged Postgres in a Fly Machine (`shared-cpu-1x`, 512 MB, $3.69) with a 3 GB volume ($0.45) | Managed Postgres starts at $38, too much for a test environment. No managed backups here, and staging data is disposable | $4.14 |
| Background jobs, WebSockets | Solid Queue and Solid Cable in the app and database above | Same as production | $0 |
| TLS and domain | Fly certs on a `*.fly.dev` hostname | Free; no custom domain needed | $0 |
| Outbound bandwidth | Fly egress | About 2 GB x $0.02 | $0.04 |
| Map tiles, geocoding | OSM tiles, Nominatim | Same as production, free at this volume | $0 |
| Error tracking and logs (optional) | `fly logs` | Optional | $0 |
| **Total** | | 2.00 + 4.14 + 0 + 0 + 0.04 + 0 + 0 | **$6.18** |

## Configuration notes

- **Secrets per environment** (`fly secrets set`): `RAILS_MASTER_KEY`, `DATABASE_URL`, `CACHE_DATABASE_URL`, `QUEUE_DATABASE_URL`, `CABLE_DATABASE_URL`, `APP_HOSTS` (comma-separated allowed hostnames).
- **Database URLs.** `config/database.yml` production block hard-codes `database:`, `username: wolfchatter` and a `WOLFCHATTER_DATABASE_PASSWORD` password; it does not read the URLs from ENV by name. It does not need to: Rails merges `DATABASE_URL` into `primary`, and `CACHE_`, `QUEUE_` and `CABLE_DATABASE_URL` into the matching named databases automatically, with the URL values (host, user, password, database name) overriding the file. All four URLs point at the same cluster and differ only in database name. Two things to do outside the config: create the three extra databases once (`fly mpg connect`, then `CREATE DATABASE`), because the Managed Postgres user may not be allowed to create them, and drop `WOLFCHATTER_DATABASE_PASSWORD` from the plan. If a URL is missing, Rails falls back to the file's defaults and fails to connect.
- **`config.hosts`** is built from the `APP_HOSTS` secret (comma-separated hostnames) in `config/environments/production.rb`, with `/up` excluded through `config.host_authorization` so health checks pass. With `APP_HOSTS` unset, no host restriction applies (Rails' production default), so set it before launch.
- **`SOLID_QUEUE_IN_PUMA=1`** must be set in `fly.toml` `[env]`; the Dockerfile does not set it, and `config/puma.rb` only loads the plugin when it is present. Without it jobs are enqueued but never run.
- **Release command** `bin/rails db:prepare` in `fly.toml`. The Docker entrypoint already runs it when the server starts, but with two machines both would run it at boot; the release command runs it once per deploy.
- **Health check** `/up` (the Rails default; its logs are already silenced). Fly's `internal_port` is 80, because the Dockerfile runs Thruster on port 80 in front of Puma.
- **`force_ssl`** is on, so cookies (including the signed name cookie) are marked Secure and Fly's proxy must terminate TLS (`assume_ssl` is also on).
- **Nominatim per environment.**
  - **Separate throttles:** the 1 request/s limit is a Solid Queue semaphore in each environment's own database. Production and staging therefore throttle separately, but share one User-Agent.
  - **Distinct User-Agents:** give each environment its own User-Agent with a contact address (set `config.x.nominatim.user_agent` from an env var such as `NOMINATIM_USER_AGENT`), or turn geocoding off in staging.
  - **One throttle per cluster:** several app machines on one cluster still share a single global throttle.
  - **Ceiling:** about 86k lookups a day. Past that, titles lag. Reaching it, or seeing room spam, is the signal to switch geocoder.
  - **Caching:** storing `place_name` on the room is the result caching that Nominatim's policy asks for.
- **Connections.** Each machine can open up to 3 threads x 4 databases = 12 connections, so 2 machines use about 24. The Basic plan's connection limit was not checked (unverified); move to Starter ($72) if it is lower.

## When this stops being enough

- **Split out a jobs process group** when place-name lookups or other jobs compete with web requests for CPU: add a `jobs` process running `bin/jobs` and unset `SOLID_QUEUE_IN_PUMA` on the web group.
- **Move to paid tiles and geocoding** when OSM or Nominatim usage nears their policies, or traffic is steady: MapTiler or a similar provider (+$30) and LocationIQ (+$100) once above 5,000 lookups per day.
- **Scale Postgres up, then out:** Basic to Starter ($72), then Launch ($282); add read replicas only after that. Solid Cable polling every 0.1 s is the first load to watch.

## Sources

All checked 2026-11-09.

- Fly Machines, volumes, bandwidth, IPv4 and certificates: <https://docs.fly.io/about/pricing>
- Fly Managed Postgres plans and storage: <https://docs.fly.io/mpg>
- Fly regions (Managed Postgres availability): <https://docs.fly.io/reference/regions/>
- MapTiler plans (Free $0 / 100k requests, Flex $30 / 500k): <https://www.maptiler.com/cloud/pricing/>
- LocationIQ plans (Free 5,000/day, Developer $100): <https://locationiq.com/pricing>
- Unverified: Machine rates in `fra`, Basic plan connection limit, tile requests per map load, and whether MapTiler's free plan allows commercial use.
