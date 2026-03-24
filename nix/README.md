# Nix support for KwaaiNet

Nix provides reproducible builds, a development shell with all dependencies
pinned, and automated tests — all from a single `flake.nix`.

## Prerequisites

[Install Nix](https://nixos.org/download/) with flake support enabled.

## Quick reference

By default, `nix build` writes every output to a single `./result` symlink —
building a different package overwrites the previous one.  A root `Makefile`
solves this by passing `-o result-<name>` to each build, giving every package
its own symlink (`result-kwaainet`, `result-map-server`, etc.) so multiple
outputs coexist.  Use `make -j` for parallel builds.

### Binaries

| Make target | Nix equivalent | Output |
|-------------|---------------|--------|
| `make` | build both binaries | `result-{kwaainet,map-server}` |
| `make kwaainet` | `nix build .#kwaainet` | `result-kwaainet` |
| `make map-server` | `nix build .#map-server` | `result-map-server` |
| `make p2pd` | `nix build .#p2pd` | `result-p2pd` |
| `make proto` | `nix build .#protoRs` | `result-proto` |

### OCI containers (Linux only)

| Make target | Nix equivalent | Output |
|-------------|---------------|--------|
| `make containers` | build both containers | `result-*-container` |
| `make kwaainet-container` | `nix build .#kwaainet-container` | `result-kwaainet-container` |
| `make map-server-container` | `nix build .#map-server-container` | `result-map-server-container` |

> **Note:** Container images use `dockerTools.streamLayeredImage` which is
> Linux-only.  On macOS (Darwin), container packages are not available.

### Tests, checks, and utilities

| Make target | Nix equivalent | Description |
|-------------|---------------|-------------|
| `make check` | `nix flake check` | smoke test + clippy + cargo test |
| `make test` | `nix run .#test-two-node` | two-node integration test |
| `make test-containers` | `nix run .#test-containers` | container image test suite |
| `make fmt` | `nix fmt` | format all Nix files |
| `make develop` | `nix develop` | enter development shell |
| `make clean` | — | remove all result symlinks |

### Nix-only targets

These have no Makefile wrapper — call `nix` directly:

| Command | Description |
|---------|-------------|
| `nix build .#cargoArtifacts` | Build only workspace dependencies (crane cache layer) |

## Outputs

```
packages.default                kwaainet CLI + bundled p2pd
packages.kwaainet               (same as default)
packages.map-server             map-server binary
packages.cargoArtifacts         cached workspace dependency artifacts (crane)
packages.p2pd                   go-libp2p-daemon (Hivemind fork)
packages.protoRs                pre-generated prost Rust code from p2pd.proto
packages.kwaainet-container     OCI image stream script — kwaainet + p2pd (Linux only)
packages.map-server-container   OCI image stream script — port 3030 (Linux only)
packages.test-two-node          two-node integration test script
packages.test-containers        container image test suite (Linux only)

devShells.default               full dev environment (Rust, Go, protobuf, etc.)

checks.clippy                   workspace-wide clippy (--deny warnings)
checks.cargoTest                workspace-wide cargo test
checks.kwaainet-smoke           sandboxed smoke test (--help, setup, identity)

formatter                       nixfmt
```

## Architecture

```
flake.nix                 orchestrator — wires modules together
Makefile                  build targets with dedicated output symlinks
nix/
  packages.nix            shared dependency lists (DRY across build + devshell)
  p2pd.nix                go-libp2p-daemon Hivemind fork (buildGoModule)
  proto.nix               protobuf codegen derivation (protoc + protoc-gen-prost)
  crane.nix               two-phase Rust build (crane: buildDepsOnly + buildPackage)
  containers.nix          OCI container images (streamLayeredImage)
  devshell.nix            nix develop environment
  shell-functions/
    ascii-art.nix         logo display on nix develop entry
  tests/
    default.nix           test orchestration — maps checks + runnable packages
    containers.nix        container image tests (load, size, run)
    smoke.nix             sandboxed: --help, setup, identity show
    two-node.nix          integration: two nodes, distinct identities, port config
```

### Design decisions

- **Crane two-phase build** — dependencies are compiled once in `buildDepsOnly`
  (keyed on `Cargo.lock`) and cached.  Source-only changes skip dependency
  compilation entirely, cutting rebuild times from ~5-10 min to ~1-2 min.
  Crane reads `Cargo.lock` directly — no `cargoHash` to maintain.
- **Per-binary packages** — the workspace binaries (kwaainet, map-server) are
  separate derivations so changes to one don't rebuild the other.
- **Minimal OCI containers** — each container includes only the binary, CA
  certificates (`cacert`), and timezone data (`tzdata`).  No shell, no
  coreutils — minimal attack surface.  Built with `streamLayeredImage` so
  there is no intermediate tarball; the output is a script that streams
  directly to `docker load` or `podman load`.
- **Modular `nix/` layout** — the flake delegates to single-purpose modules
  (following the pattern used by the redpanda and xdp2 Nix setups).
- **Separate p2pd derivation** — the upstream `build.rs` clones a Git repo and
  runs `go build` at Rust compile time.  Nix builds are sandboxed (no network),
  so we build p2pd as an independent `buildGoModule` and patch `build.rs` to
  point at it.  This also means `p2pd` is cached independently.
- **Protobuf codegen as a separate derivation** — the upstream `build.rs` runs
  `protoc` via `prost_build` to generate Rust types from `p2pd.proto`.  The
  `proto.nix` derivation runs `protoc` + `protoc-gen-prost` (both from nixpkgs)
  to produce `p2pd.pb.rs`.  Because Nix tracks the hash of the proto source
  directory, the derivation automatically rebuilds whenever `p2pd.proto` changes.
  The `crane.nix` patches `build.rs` to copy this pre-generated file instead of
  running `prost_build`, eliminating `protobuf` as a build-time dependency of
  the Rust package.
- **`packages.nix` as single source of truth** — build inputs are defined once
  and shared by `crane.nix` and `devshell.nix`.
- **Smoke test in sandbox, integration tests outside** — the smoke test verifies
  the binary works without network access (`nix flake check`).  The two-node
  test and container tests need runtime resources (localhost networking, container
  runtime) so they are runnable scripts, not sandboxed checks.
- **Version from Cargo.toml** — `crane.nix` reads the workspace version via
  `builtins.fromTOML`, so the Nix package version stays in sync automatically.

## First build — filling in hashes

Nix requires content hashes for reproducibility.  On the first build, only the
p2pd Go module hashes need to be set:

1. **`nix/p2pd.nix` → `vendorHash`** — run `nix build .#p2pd` and copy the
   expected hash from the error message.

The Rust build uses crane, which reads `Cargo.lock` directly — no hash to
maintain.  When Cargo dependencies change, rebuild is automatic.

## Multi-architecture support

The flake uses `flake-utils.lib.eachDefaultSystem`, which covers native builds
on `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, and `aarch64-darwin`.

## OCI containers

Each binary is available as a minimal OCI container image built with
`streamLayeredImage`.  Images contain only the binary, CA certificates, and
timezone data — no shell, no coreutils.

> **Note:** Container images are Linux-only (`dockerTools.streamLayeredImage`
> requires Linux).  On macOS, container packages are not available.

```bash
# Build and load a container image
make kwaainet-container
./result-kwaainet-container | docker load    # or: podman load
docker run --rm kwaainet:0.3.25 --help

# Build all containers in parallel
make -j containers

# Run the container test suite (requires podman or docker)
make test-containers
```

Container images are tagged with the workspace version from `core/Cargo.toml`
(e.g., `kwaainet:0.3.25`).

| Container | Exposed port | Contents |
|-----------|-------------|----------|
| `kwaainet` | — | kwaainet binary + bundled p2pd |
| `map-server` | 3030/tcp | map-server binary |

All containers include `SSL_CERT_FILE` and `TZDIR` environment variables
pre-configured for TLS and log timestamps.

## Development workflow

```bash
# Enter dev shell with Rust, Go, protobuf, and formatters
nix develop

# Build from source (inside dev shell, same as non-Nix workflow)
cd core
cargo build
cargo test --all

# Format Nix files
nix fmt

# Build via Makefile (preferred — uses dedicated output symlinks)
make kwaainet
./result-kwaainet/bin/kwaainet --help
```

## Tests

### Smoke test (sandboxed)

```bash
make check    # or: nix flake check
```

Verifies `kwaainet --help`, `setup`, `identity show`, and `config show` all
succeed without network access.  Also runs workspace-wide clippy and cargo test.

### Two-node integration test

```bash
make test    # or: nix run .#test-two-node
```

Creates two isolated node environments with separate `HOME` directories,
generates distinct identities, configures different P2P ports, starts both
nodes, and verifies they are running.

### Container image test

```bash
make test-containers    # or: nix run .#test-containers
```

Requires `podman` or `docker`.  For each container image:
1. Streams and loads the image into the container runtime
2. Verifies the image size is under 200 MB
3. Runs the binary inside the container to verify it starts

## Updating dependencies

Nix pins every input via `flake.lock`.  The sections below cover the kinds of
update you will encounter.

### Updating nixpkgs (and other flake inputs)

```bash
# Update all flake inputs (nixpkgs, flake-utils, crane) to latest
nix flake update

# Update only nixpkgs
nix flake update nixpkgs

# Pin nixpkgs to a specific commit
nix flake update nixpkgs --url github:NixOS/nixpkgs/<commit>
```

After updating, rebuild to verify nothing broke:

```bash
make all && make check
```

Commit the updated `flake.lock` alongside any other changes.

### Updating Rust (Cargo) dependencies

When `core/Cargo.lock` changes (new crate versions, added/removed deps), crane
picks up the changes automatically — no hash to update.  Just rebuild:

```bash
cd core && cargo update && cd ..
make all
```

### Updating the p2pd (Go) dependency

If the go-libp2p-daemon fork bumps its version or Go module dependencies:

1. Update `version`, `rev`, and `hash` in `nix/p2pd.nix`.
   - To get the new source `hash`, temporarily set it to `""` and run
     `nix build .#p2pd` — Nix prints the correct hash.
2. Update `vendorHash` the same way — set to `""`, build, copy the hash.
3. Rebuild: `make all`

### Updating protobuf definitions

When `core/crates/kwaai-p2p-daemon/proto/p2pd.proto` changes, no manual action
is needed — Nix tracks the source hash and automatically rebuilds the `protoRs`
derivation (and anything that depends on it) on the next build.

To verify the generated code independently:

```bash
make proto
ls result-proto/
```

### Quick-reference: which hash lives where

| What changed | File to update | Field |
|---|---|---|
| `flake.lock` inputs | (auto via `nix flake update`) | — |
| `core/Cargo.lock` | (automatic — crane reads Cargo.lock) | — |
| p2pd Go source | `nix/p2pd.nix` | `hash` |
| p2pd Go modules | `nix/p2pd.nix` | `vendorHash` |
| `p2pd.proto` | (automatic — no hash to update) | — |
