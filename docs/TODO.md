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

## Networking

- [ ] **Fix relay fallback** — `metro@kwaai` (peer `...5bZ251`) connects via p2p-circuit relay through `76.91.214.120` instead of direct on configured public IP `75.141.127.202:8080`. Node should establish a direct connection. Investigate NAT traversal / port forwarding and `announceAddrs` config.
