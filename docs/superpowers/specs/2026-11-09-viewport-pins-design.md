# Viewport pins and clustering: design

Date: 2026-11-09 · Status: proposed · Resolves review finding **Q1** ([`docs/review/notes.md`](../../review/notes.md))

## Why

Every map page renders a marker element for every room. The self-review measured this at 10k rooms:
about 220 ms of server time and 3.7 MB of HTML (173 KB gzipped). The browser then creates a Leaflet
marker for each room. That holds at today's scale, but it grows linearly with rooms. Past a few
thousand rooms the zoomed-out map is also a solid smear of pins that nobody can click.

Loading only the visible area is not enough on its own. Zoomed out to the world, everything is
visible. So the server also groups rooms into clusters when there are too many to show one by one.

## Goals

- Map pages render a fixed amount of pin data, however many rooms exist.
- Zoomed out, nearby rooms merge into a **cluster marker showing a count**. Clicking a cluster zooms
  in, and clusters split into smaller ones and finally into ordinary pins.
- Zoomed in, the user sees ordinary pins for the visible area only. Every pan or zoom loads the new
  area.
- Live updates still work (lead developer's decision):
  - **Clustered view:** creating a room raises the count of the cluster it falls in for everyone
    watching. If no cluster covers that spot, a cluster of 1 (shown as a pin) appears.
  - **Pin view:** a new room's pin appears only if it is inside the viewer's current view. Off-screen
    rooms are ignored until the viewer pans there.
  - Geocoded titles still re-title a visible pin live.

## Non-goals

- Place names on clusters. That would need extra geocoding; clusters show counts only.
- Animated cluster splitting (the Leaflet.markercluster look).
- PostGIS, Redis, a Node build, or a JSON API. The CLAUDE.md stack rules stand.
- Removing pins live. Rooms are never deleted.

## Anti-goals

The change fails, even if it works, if:

- small maps look worse than today. With a few dozen rooms the user must see the same individual
  pins as now, at every zoom;
- a deep link (`/chatrooms/:id`) opens with that room's pin not on screen;
- panning makes pins flicker or vanish while the next area loads;
- it reintroduces an N+1 or a query that scales with total rooms on any request.

## Constraints

- Hotwire first (CLAUDE.md). Pins and clusters stay **server-rendered marker elements** with data
  attributes, delivered as a Turbo Stream. No JSON endpoint, no client-side store beyond Leaflet's
  own layers.
- Plain PostgreSQL. Coordinates are `decimal(10,6)` columns.
- Prosopite stays on. Every new query is bounded and indexed.
- The PRD, spec and CLAUDE.md must be updated to match. The PRD currently says FR-1 "map loads
  showing all existing pins", lists "pin clustering" as a non-goal, and lists unbounded loading as an
  accepted risk.

## Design

### Decided with the lead developer

1. **Grouping happens on the server.** The browser never downloads every room. (Considered and
   rejected: the Leaflet.markercluster plugin. It looks the same, but it still ships every pin, so
   it fixes the clutter and not the load.)
2. **Clusters show a count.** Clicking one zooms in.
3. **Live behaviour** as in Goals.

### Request flow

- The map page no longer renders all rooms into `#markers`. It renders the map, the empty
  `#markers` container, and the panel. The panel keeps its own marker for its room, so a deep-linked
  room is always pinned.
- After the map is ready, and after every `moveend` (debounced about 250 ms, with any in-flight
  request aborted), the map controller requests the visible area:
  `GET /chatrooms/markers?south=…&west=…&north=…&east=…&zoom=…`, accepting
  `text/vnd.turbo-stream.html`. It renders the reply with `Turbo.renderStreamMessage`.
- The reply is a single `turbo-stream action="update" target="markers"` holding either pin elements
  (the existing `_marker` partial) or cluster elements (a new `_cluster` partial). The `#markers`
  container carries the mode (`pins` or `clusters`) and, in cluster mode, the cell size, so the
  client can apply live updates.
- When the new set arrives, the map controller swaps the layer in one step: build the new layer,
  add it, then remove the old one. The panel room's pin is never removed.

### Pins or clusters

- **Adaptive, not a fixed zoom threshold** (my call). The server counts rooms in the bounding box.
  If there are `PIN_LIMIT` or fewer (starting value 300), it returns pins. Otherwise it returns
  clusters. This keeps small maps exactly as they are today at every zoom, which covers the first
  anti-goal, and switches to clusters only where density demands it.
- **Clusters come from a grid over latitude and longitude.** The cell size in degrees comes from the
  zoom: `360 / 2**zoom × (CELL_PX / 256)`, with `CELL_PX` around 80. One `GROUP BY` query returns,
  per occupied cell: the count, the average lat and lng (where the cluster is drawn), and `MIN(id)`.
- A cell holding exactly **one** room renders as an ordinary pin. That needs its title and URL, which
  a second bounded query loads by id. A lone room is never shown as a "1" bubble.
- **At most** `PIN_LIMIT` pins or clusters per reply. A plain degree grid makes cells look taller at
  high latitudes on a Mercator map. That's acceptable.
- **Index:** a composite B-tree on `(latitude, longitude)`.

### Bounding-box parameters

- `south`, `west`, `north`, `east` and `zoom` are required and numeric. Latitude is clamped to
  [-90, 90]. A non-numeric or missing value returns 400. Zoom must be an integer from 0 to 19.
- **Antimeridian:** Leaflet bounds can run past ±180 when the world wraps. The client sends
  `getBounds()` wrapped per corner. When `west > east` the server queries two longitude ranges. If
  the box spans 360° or more, longitude is unrestricted.
- The endpoint is read-only and cheap (two indexed queries), so it gets no rate limit. Revisit this
  if abuse shows up. Map pages and this endpoint send `no-cache`.

### Live updates

- Room creation still broadcasts one marker element on the global `chatrooms` stream. It is no longer
  appended to `#markers`, because a refresh would wipe it. It goes to a separate hidden `#live_markers`
  container, which is pruned so it holds only the last few elements. The `marker` controller still
  dispatches `marker:connect`.
- The map controller decides what to do with it:
  - **Pin mode:** add the pin if it is inside the current bounds (deduped by id, as today).
    Otherwise ignore it.
  - **Cluster mode:** compute the room's grid cell with the same formula and cell size the server
    sent, then increment that cluster's count. If the cell is empty, add a lone pin.
  - Counts may drift from the truth between fetches. The next pan or zoom reconciles them.
- **Title updates:** the existing `broadcast_replace_to "chatrooms"` that targets the room's marker
  element is kept, re-titling a visible pin. If the element isn't on the page, Turbo ignores it.
- **Creator:** the creator's own room shows through the panel marker, as today.

### Deep links

On a full page load of `/chatrooms/:id`, the map centres on that room at the current default zoom.
Today it always opens at [48, 15]. (My call. It is required by the second anti-goal.) The index page
keeps today's default view.

### Clicking a cluster

It zooms in by 2 levels centred on the cluster, capped at the max zoom. Clicking a cluster must not
create a room. Leaflet marker clicks don't reach the map's click handler, but a test must pin this
down.

## Testing (expected shape)

- **Model and query tests:**
  - pins inside the box only;
  - antimeridian split;
  - switching from pins to clusters at `PIN_LIMIT`;
  - grid grouping;
  - lone-room cells rendered as pins;
  - a constant number of queries per request (Prosopite plus a query-count assertion).
- **Controller tests:**
  - 400 for missing or bad params;
  - a Turbo Stream reply only (406 otherwise, as elsewhere);
  - the `no-cache` header.
- **System tests:**
  - a sparse map shows individual pins as before;
  - a dense area shows a cluster with a count;
  - clicking a cluster zooms in until pins appear;
  - panning loads pins in the new area;
  - live: in cluster mode, another viewer's new room raises a count; in pin mode, an off-screen room
    doesn't appear and an on-screen one does;
  - a deep link centres on its room.

  Dense data comes from an `insert_all` in the test, not from fixtures.
- **Benchmark:** re-run the Q1 probe at 10k rooms. Record the size and time of the map page and of a
  world-view markers request in the review notes.

## Docs to update

- **PRD:**
  - FR-1: the map shows the pins in view, clustered when dense;
  - FR-8: the live rules above;
  - drop "Pin clustering" from the non-goals;
  - drop the unbounded-loading risk;
  - update the global-stream paragraph.
- **Design spec:** the non-goals list and the "all existing pins" wording.
- **CLAUDE.md, "Live map pins" convention:** pins and clusters are marker elements fetched per
  viewport as a Turbo Stream into `#markers`. Live pins go to `#live_markers`. There is still no JSON
  endpoint.
- **`docs/review/notes.md`:** Q1 moves to Fixed, with the benchmark figures.
- **README:** the architecture diagram and the decisions table (the "pins as marker elements" row).

## Settled after the builder check (my calls)

1. **Panel pin.** The panel's room has its own Leaflet layer, outside the swapped layer, so the
   swap never removes it. In pin mode, a fetched pin with the same id is skipped. In cluster mode the
   panel pin is drawn on top of the cluster that also counts it. It's the room you're in, so showing
   it twice is intended.
2. **Live pins versus a refetch.** The refetch replaces the layer. Any live room whose broadcast
   arrived after the fetch request was sent is applied again after the swap, so a room created
   mid-fetch never vanishes.
3. **Finding a cluster's cell.** Cluster elements, and pin elements in cluster mode, carry
   `data-cell-x`/`data-cell-y`. The client finds the cluster by cell index, not by position. A live
   room landing in a lone pin's cell turns that pin into a "2" cluster.
4. **Grid origin and cap.** Cells use a global origin: `floor(lat / size)` and `floor(lng / size)`.
   This keeps clusters stable across pans and lets the client compute the same cell as the server.
   If the box's grid could hold more than `PIN_LIMIT` cells, the server doubles the cell size until
   it fits. This is arithmetic on the box, done before any query. The cell size it used goes on `#markers`, so live increments use the same grid. Replies are
   never silently truncated.
5. **Deep-link centring happens only on a full page load,** when the Leaflet map is first created.
   Frame visits between rooms never move the map (the container is permanent). Zoom stays at the
   default (5).
6. **Pruning `#live_markers`.** The map controller does it after handling each live marker and keeps
   the last 20.

## Left to the builder

- Exact `PIN_LIMIT`, `CELL_PX` and debounce values.
- Cluster marker styling. A Leaflet `divIcon` with Tailwind classes, sized by count band, is the
  expected route. It must be readable on OSM tiles.
- How a cluster's count element is updated in place on live increments.
- Whether the two pin queries (count, then fetch) are merged into one capped fetch of `PIN_LIMIT + 1`
  rows.
