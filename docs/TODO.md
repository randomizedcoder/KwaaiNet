# TODO

## Installation

- [ ] **Bundle `p2pd` in release tarball** — `DAEMON_BINARY_PATH` is baked in at compile time (`env!("P2PD_PATH")`) pointing to the build output dir. When `kwaainet` is installed on a clean machine the path doesn't exist and the node fails to start. Fix options: (1) include `p2pd` alongside `kwaainet` in the release archive, (2) resolve at runtime by searching `~/.local/bin`, `/usr/local/bin`, same dir as `kwaainet` binary, then fall back to compile-time path.

## map.kwaai.ai — Public Web UI

> v1 shipped: DHT crawler (`core/crates/map-server`), React SPA (`apps/map`).
> The items below are grouped by phase and approximate complexity.

### Backend — map-server (`core/crates/map-server`)

#### Quick wins
- [ ] **Remove debug log spam** — `crawler.rs` still emits per-result `DEBUG` lines for every DHT response. Gate behind `tracing::trace!` or remove before production deploy.
- [ ] **Fix `-0.0` tokens/sec** — `cache.rs` sums an empty set of floats, producing `-0.0`. Guard with `if nodes.is_empty() { 0.0 } else { sum }`.
- [ ] **Rate-limit `/api/nodes`** — response can be large. Add `tower_http::limit` or cache the serialised JSON for 5 s.
- [ ] **CORS lockdown** — `ALLOWED_ORIGINS` env var exists but defaults to `*`. Set to `https://map.kwaai.ai` in the production Dockerfile / compose file.
- [ ] **Graceful shutdown** — handle `SIGTERM` so the server drains in-flight WebSocket connections before exit (important for zero-downtime deploys).

#### Crawler improvements
- [ ] **Accurate trust tier** — current `tier_from_vc_count(n)` is a rough proxy. Import `kwaai-trust::TrustScore::from_credentials()` and decode the `trust_attestations` field from the DHT value to compute a real score.
- [ ] **Version field** — decode `version` from the DHT map and expose it in `NodeEntry`. Needed for `map.kwaai.ai` to surface stale nodes (see MEMORY.md "Peer version visibility").
- [ ] **Crawl own local storage** — in addition to querying bootstrap peers, query the local `DHTStorage` (via p2pd) so the running node always appears even if bootstrap propagation lags.
- [ ] **Configurable bootstrap peers** — read `~/.kwaainet/config.yaml` at startup (or accept a `--config` flag) to inherit the user's `initial_peers` list rather than using only defaults.
- [ ] **Crawl all registered models dynamically** — `_petals.models` registry discovery is implemented but only runs once. Re-query every crawl cycle so newly registered models are picked up without a server restart.
- [ ] **Persist cache across restarts** — write the node cache to a small SQLite file (via `rusqlite`) so the map is not empty for the first 60 s after a restart.

#### API additions (v2)
- [ ] **`GET /api/nodes/:peer_id`** — individual node detail page (trust certs, uptime history, version).
- [ ] **`GET /api/coverage`** — block coverage bitmap as a compact JSON array; used by a future coverage heatmap widget.
- [ ] **`POST /api/v1/state`** — receive heartbeat pings from running nodes (the `health_monitoring.api_endpoint` already points here). Validate and upsert into cache so nodes are visible immediately on start rather than waiting for the 60 s crawl.
- [ ] **WebSocket auth** — currently `/api/live` is fully open. For v2 operator dashboard, add an optional `?token=` query param checked against a shared secret.

---

### Frontend — React SPA (`apps/map`)

#### Quick wins
- [ ] **Favicon** — `public/favicon.svg` is referenced in `index.html` but not created. Add an SVG version of the Kwaai tree logo.
- [ ] **Negative-zero display** — mirror the backend fix; also guard `tokens_per_sec.toFixed(1)` to show `0.0` not `-0.0`.
- [ ] **WebSocket reconnect indicator** — show a subtle "reconnecting…" badge in the hero stat bar when `connected === false`, instead of silently showing stale numbers.
- [ ] **Responsive nav** — mobile hamburger menu; nav links currently hidden on small screens.
- [ ] **Accessibility** — add `aria-label` to all icon-only buttons (copy, remove drive, CTAs). Run `axe` or Lighthouse audit.

#### HeroSection / NetworkGraph
- [ ] **Node tooltip on hover** — show peer name, trust tier, throughput, version in a floating tooltip when hovering a graph node.
- [ ] **Click-to-highlight** — clicking a node in the graph highlights its block range in a coverage bar below the counter chips.
- [ ] **Live pulse animation** — nodes with `throughput > 0` should visually pulse; currently the glow is drawn every frame. Implement a CSS animation driven by `throughput` magnitude.
- [ ] **Coverage bar** — a horizontal bar below the stats chips showing block 0–79 coloured by how many nodes cover each block (green = covered, red = gap). Uses `GET /api/coverage`.
- [ ] **Node count history sparkline** — tiny 24 h sparkline next to the node counter, fed by a rolling window stored in localStorage.

#### BenchmarkSection
- [ ] **WebGL fallback** — the CPU fallback is very slow on low-end machines. Implement a WebGL GEMM path using `twgl.js` as the middle tier between WebGPU and pure CPU.
- [ ] **Calibrate tps estimate** — the 128×128 GEMM → token/sec extrapolation is rough. Gather empirical data from known hardware (M2, RTX 4090, etc.) to fit a better conversion factor.
- [ ] **Storage: show browser quota vs disk quota** — `navigator.storage.estimate().quota` is typically 60 % of available disk space. Show both figures and clarify the difference to the user.
- [ ] **Persist benchmark results** — save to `localStorage` so the results panel is visible on return visits without re-running.
- [ ] **Share results** — "Share my score" button that generates a shareable URL with tps/storage params encoded (no server needed).

#### TrustGraphSection
- [ ] **Real endorsement edges** — `PeerEndorsementVC` relationships from `/api/nodes` should draw directed edges between nodes, not just adjacency edges. Decode the VC subject/issuer DIDs and map to peer IDs.
- [ ] **Tier filter** — checkbox row to show/hide nodes by tier (Unknown / Known / Verified / Trusted).
- [ ] **ToIP explainer** — add a collapsible "How it works" panel below the graph explaining the 4-layer ToIP stack in plain language, linking to `docs/WHITEPAPER.md`.

#### InstallSection
- [ ] **Live installer URL** — fetch latest release tag from GitHub API (`/repos/Kwaai-AI-Lab/KwaaiNet/releases/latest`) and inject the real version into the install commands instead of hardcoded `main` branch URL.
- [ ] **Node live detection** — after install, poll `/api/nodes` every 10 s for a peer ID stored in `localStorage` post-install. When found, show a "Your node is live!" celebration toast and unlock the `node_live` gamification state.
- [ ] **Gamification state machine** — implement the full `teaser → benchmarked → installed → node_live` progression with achievement badge chips (see plan). State persisted in `localStorage`.
- [ ] **Windows PowerShell copy** — the copy button currently copies the `curl` command even when Windows tab is selected. Fix to copy the `irm | iex` command.

---

### Infrastructure & Deployment

- [ ] **`deploy-map.yml` GitHub Actions workflow** — on push to `main`, build `Dockerfile.map-server` and `Dockerfile.map-frontend`, push to GHCR, SSH-deploy to `map.kwaai.ai` host.
- [ ] **`docker-compose.map.yml`** — single compose file to run `map-server` + `nginx` frontend + `kwaainet` (for p2pd) on the production host. Include health checks and restart policies.
- [ ] **TLS / HTTPS** — `docker/map-nginx.conf` serves plain HTTP. Add Certbot / Let's Encrypt auto-renewal for `map.kwaai.ai`.
- [ ] **Environment secrets** — document required env vars (`BIND_ADDR`, `ALLOWED_ORIGINS`, `BOOTSTRAP_PEERS`, `TOTAL_BLOCKS`) in a `.env.example` file.
- [ ] **Map-server in workspace dist config** — `map-server` is not in `[workspace.metadata.dist]` targets. Decide whether to ship it as a release binary or Docker-only.

---

### v2 — Operator Dashboard (auth required)

- [ ] **Passkey / WebAuthn registration** — reuse `summit-server` WebAuthn flow. Add `POST /api/auth/begin` + `/complete` to map-server, or proxy to summit-server.
- [ ] **Operator node binding** — `POST /api/node/claim` lets an authenticated user claim their peer ID. Stored in SQLite alongside the node cache.
- [ ] **Private stats panel** — authenticated route `/dashboard` showing uptime history, per-block throughput, earnings ledger, and VC status for the operator's own node.
- [ ] **VC issuance trigger** — operator dashboard shows a "Request VerifiedNodeVC" button that initiates the issuance flow via summit-server.

---

### v3 — Trust Registry

- [ ] **TRQP endpoint** — `GET /api/trust/:did` implements the Trust Registry Query Protocol so other agents can verify KwaaiNet node DIDs against the live registry.
- [ ] **Verifiable Relationship Credentials** — extend the DHT wire format to carry `PeerEndorsementVC` data between peers. Visualise the resulting endorsement graph on the map.
- [ ] **EigenTrust propagation** — implement Phase 4 of `kwaai-trust` (transitive endorsement scoring) and feed scores into the D3 trust graph node sizes.

---

## map.kwaai.ai — v2 Rewrite

> Full requirements: `docs/MAP_SERVER_V2_REQUIREMENTS.md`
> Replaces: OpenAI-Petal `docker/kwaainet_health/` (Python/Flask + vanilla JS + Leaflet)
> Source to port from: `../OpenAI-Petal`

### Map View (Phase 2 — port + upgrade from OpenAI-Petal)
- [ ] **Improved geo-location accuracy** — upgrade IP→lat/lon resolution; fall back to `announce_addr` multiaddr parsing before IP-geolocation DB lookup.
- [ ] **Pin images** *(optional)* — custom marker icons per trust tier (Unknown / Known / Verified / Trusted); SVG icons served from `/static/`.
- [ ] **Traffic heatmap** — overlay tokens/sec per geographic cell using a weighted heatmap layer (MapLibre `heatmap` layer or Leaflet.heat); intensity driven by `throughput_tps` field from `/api/nodes`.
- [ ] **Bootstrap diagnostics on mouse-over** — hovering a bootstrap peer marker shows a tooltip with: peer_id, uptime, peers_known, last_seen, latency to server; data from `GET /api/bootstrap/:peer_id`.

### Table View (Phase 2 — port + upgrade from OpenAI-Petal)
- [ ] **Summary stats row** — pinned header row showing network totals: total nodes (direct + relay counts separate), total tokens/sec, total storage capacity (GB).
- [ ] **Direct vs relay node count** — distinguish `direct` (reachable via public IP) from `relay` (circuit-relay only) in both the summary row and per-row badge.
- [ ] **Total tokens/sec column** — per-node `throughput_tps` column with network total in the summary row; fix `-0.0` display.
- [ ] **Total storage capacity column** — per-node `capacity_gb` from VPK info; network total in summary row.
- [ ] **Version column** — decode `kwaainet_version` from DHT map (see MEMORY.md "Peer version visibility"); highlight stale versions in amber.
- [ ] **Uptime column** — `first_seen` → uptime duration string (e.g. `3d 14h`); updated live via WebSocket.
- [ ] **Blocks capability column** — show block capability as a compact chip list (e.g. `0–31`, `32–63`) rather than raw start/end integers; colour-coded by coverage gaps.

### Backend hardening (Phase 1)
- [ ] **WebSocket diff protocol** — replace full-snapshot push every 5 s with compact add/update/remove diffs; reduces bandwidth ~95% for established connections.
- [ ] **`GET /api/nodes/:peer_id`** — individual node detail: VC list, 24 h throughput history, uptime.
- [ ] **`GET /api/coverage`** — block 0–79 coverage bitmap (`u8[80]` count per block); drives coverage heatmap widget.
- [ ] **`POST /api/v1/state`** — heartbeat ingest from running nodes; upserts into cache immediately so nodes appear within seconds of starting, not after the 60 s crawl.
- [ ] **SQLite persistence** — write node cache + 24 h throughput history to `rusqlite`; no cold-start blank map after server restart.
- [ ] **Rate-limit `/api/nodes`** — 5 s pre-serialised byte cache; single goroutine reserialises; `tower` middleware.
- [ ] **CORS lockdown** — set `ALLOWED_ORIGINS=https://map.kwaai.ai` in production Dockerfile.

### 3D Globe hero (Phase 2)
- [ ] **Replace flat NetworkGraph with `globe.gl`** — Three.js 3D globe, nodes as luminous dots (size = throughput, colour = trust tier), rotating hero element.
- [ ] **Inference arc animation** — geodesic lines connecting coordinator → shard nodes during active sessions; synthesised from `/api/live` session data.
- [ ] **Coverage heatmap bar** — blocks 0–79 coloured by coverage count (green ≥ 2 nodes, amber = 1, red = gap); clicking a block highlights serving nodes on globe.
- [ ] **Node detail side panel** — click globe node → slide-in panel with peer_id, blocks, throughput, version, VPK, VC count, first/last seen, 24 h sparkline.
- [ ] **Operator search + deep link** — search by peer_id / public_name / IP; `?node=Qm...` URL; globe flies to matching node.
- [ ] **OffscreenCanvas worker** — Three.js globe in offscreen canvas to keep main thread free.

### Engagement & conversion (Phase 3)
- [ ] **Real endorsement edges in trust graph** — decode `PeerEndorsementVC` subject/issuer DIDs from `/api/nodes`; draw directed arrows; tier filter checkboxes.
- [ ] **WebGL GEMM benchmark fallback** — twgl.js middle tier between WebGPU and CPU for Safari/Firefox users.
- [ ] **Benchmark localStorage persist + share URL** — save results across sessions; "Share my score" encodes tps/storage in URL params.
- [ ] **Calibrated tps conversion factor** — empirical data from known hardware (M2, RTX 4090, A100) to fit better tokens/sec estimate.
- [ ] **Install funnel: GitHub Release API version** — fetch latest tag dynamically instead of hardcoded `main` branch URL.
- [ ] **Gamification state machine** — `teaser → benchmarked → installed → node_live`; achievement chip badges; `node_live` detected by polling `/api/nodes` for stored peer ID.
- [ ] **Windows PowerShell copy fix** — copy button copies curl command even on Windows tab; fix to copy `irm | iex` command.

### Polish & accessibility (Phase 4)
- [ ] **Framer Motion entrance animations** — panels slide/fade in; globe nodes lerp to new positions.
- [ ] **`prefers-reduced-motion` support** — disable arc animations and globe auto-rotation.
- [ ] **WCAG 2.1 AA audit** — `aria-label` on all icon-only buttons; keyboard nav for globe; contrast check.
- [ ] **Mobile responsive nav** — hamburger menu; sections stack on small screens.
- [ ] **Favicon** — `public/favicon.svg` SVG version of Kwaai tree logo.
- [ ] **Lighthouse ≥ 90** — bundle < 300 KB gzip JS, < 50 KB CSS; virtual DOM diff only for side panel.

---

## Bootstrap Server v2 — Rust Port & Radical Reimagination

> Full requirements: `docs/BOOTSTRAP_SERVER_V2_REQUIREMENTS.md`
> Replaces: OpenAI-Petal `docker/kwaainet_bootstrap/` (50-line shell wrapper around `petals.cli.run_dht`)
> New crate: `core/crates/kwaai-bootstrap/`

### Phase 1 — Drop-in Rust replacement
- [ ] **New crate `kwaai-bootstrap`** — `core/crates/kwaai-bootstrap/`; add to workspace; CLI: `kwaainet bootstrap serve / keygen / status`.
- [ ] **Ed25519 key management** — replace RSA-2048 with Ed25519; same libp2p peer ID derivation (`SHA256(protobuf(pubkey))`); key stored at `~/.kwaainet/bootstrap-identity.bin`.
- [ ] **Existing peer ID compatibility** — wrap existing RSA keys or run graceful handoff window so established nodes do not need config changes.
- [ ] **Kademlia DHT node** — reuse `kwaai-hivemind-dht`; persist routing table to SQLite; survives restart in < 2 s.
- [ ] **Health endpoint** — `GET /health → { status, peers_known, uptime_secs }`; Prometheus metrics on `:9090`.
- [ ] **Docker image + deploy** — `Dockerfile.bootstrap`, add to `deploy-map.yml` or separate `deploy-bootstrap.yml`.
- [ ] **Verify drop-in** — existing `kwaainet` nodes connect without config change after DNS swap.

### Phase 2 — Privacy layer
- [ ] **PoW challenge** — adaptive difficulty (target 50 ms solve on modern CPU); stateless verify (recompute from timestamp epoch); no heap alloc on bad requests.
- [ ] **TrustedNodeVC fast-lane** — peers with valid VC skip PoW; verified against trust registry signature, no live RPC.
- [ ] **Encrypted introduction protocol** — ephemeral X25519 key exchange; response encrypted to ephemeral pubkey; bootstrap never logs joining IPs; `intent_hash = SHA256(model_prefix)`.
- [ ] **Signed peer-list responses** — Ed25519 signature over response; peers verify before using list; protects against BGP hijack / MITM.
- [ ] **No persistent IP logging** — enforce in code (`log_joins = false` default); document in privacy policy.
- [ ] **Rate limiting at socket layer** — 10 introductions/IP/min, 1000/IP/hr; enforced before any heap allocation.

### Phase 3 — Federation
- [ ] **`_kwaai.bootstrap.nodes` DHT key** — community bootstrap nodes self-register; existing nodes auto-discover via DHT crawl.
- [ ] **`BootstrapOperatorVC` issuance** — `kwaainet bootstrap register --vc <path>` submits to summit-server; returns `BootstrapAdmissionVC`.
- [ ] **Federation API** — `GET /api/federation/nodes`, `POST /api/federation/register`, `DELETE /api/federation/nodes/:peer_id` (Kwaai admin).
- [ ] **VC revocation** — revoked `BootstrapAdmissionVC` causes nodes to stop using that bootstrap within 60 s (next DHT crawl).
- [ ] **Geographic distribution** — deploy Kwaai-operated nodes in US-West, US-East, EU-West, AP-Southeast; anycast DNS (`bootstrap.kwaai.ai`).
- [ ] **Community capacity target** — design for ≥ 50% of introductions served by community nodes.

### Phase 4 — Peer cache gossip (bootstrap-free rejoin)
- [ ] **Peer cache gossip protocol** — nodes broadcast signed peer-list snapshot to 3 random peers every 5 min; receivers merge, keep 100 most recent entries.
- [ ] **Signed cache entries** — originating peer signs; receiver verifies before merging; wire format MessagePack.
- [ ] **Bootstrap-free rejoin** — on restart, attempt cached peers before contacting bootstrap; only truly new nodes require bootstrap.
- [ ] **Cache persistence** — store peer cache at `~/.kwaainet/peer-cache.json`; survives node restart.
- [ ] **Deprecate always-bootstrap-on-restart** — update `kwaainet start` to try peer cache first; bootstrap is fallback.

---

## Networking

- [ ] **Fix relay fallback** — `metro@kwaai` (peer `...5bZ251`) connects via p2p-circuit relay through `76.91.214.120` instead of direct on configured public IP `75.141.127.202:8080`. Node should establish a direct connection. Investigate NAT traversal / port forwarding and `announceAddrs` config.
