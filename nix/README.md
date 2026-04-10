# Nix support for KwaaiNet

Nix provides reproducible builds, a development shell with all dependencies
pinned, and automated tests — all from a single `flake.nix`.

## Goals

The goals of using Nix in this repository are to:
- **Simplify onboarding** — make it easy to get started with KwaaiNet on any
  Linux or macOS system
- **Improve reproducibility** — ensure consistent build environments across
  developers (no more "it worked on my machine")
- **Reduce setup friction** — eliminate dependency conflicts and version
  mismatches; a single `nix build` or `nix develop` is all you need

Feedback and pull requests are welcome.  If we're missing a tool, please open
an issue or PR.  See `nix/packages.nix` for package definitions.

---

## Getting started

### 1. Install Nix

Choose **multi-user** (daemon) or **single-user**:

- **Multi-user install** (recommended on most distros):
  ```bash
  bash <(curl -L https://nixos.org/nix/install) --daemon
  ```

- **Single-user install**:
  ```bash
  bash <(curl -L https://nixos.org/nix/install) --no-daemon
  ```

See also: [Nix installation manual](https://nix.dev/manual/nix/2.24/installation/)

#### Video tutorials

| Platform | Video |
|----------|-------|
| Ubuntu | [Installing Nix on Ubuntu](https://youtu.be/cb7BBZLhuUY) |
| Fedora | [Installing Nix on Fedora](https://youtu.be/RvaTxMa4IiY) |

### 2. Enable flakes (if needed)

Nix flakes are an opt-in feature.  If you haven't enabled them yet:

**Option A — one-time flag** (no config change):
```bash
nix --extra-experimental-features 'nix-command flakes' develop .
```

**Option B — permanent** (recommended):
```bash
test -d /etc/nix || sudo mkdir /etc/nix
echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf
```

After this, all `nix build`, `nix develop`, and `nix flake` commands work
without extra flags.

See also: [Nix Flakes Wiki](https://nixos.wiki/wiki/flakes)

### 3. Build or enter the dev shell

```bash
# Build kwaainet (produces ./result/bin/kwaainet)
nix build

# Or enter a development shell with Rust, Go, protobuf, and formatters
nix develop
```

### 4. First run considerations

On first execution, Nix will download and build all dependencies — this can
take several minutes depending on your internet speed.  On subsequent runs Nix
reuses its cache in `/nix/store/` and startup is essentially instantaneous.

Nix will **not** interact with any system packages you already have installed.
The Nix versions are isolated and effectively "disappear" when you exit the
development shell.

---

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
| `make containers` | build all containers | `result-*-container` |
| `make kwaainet-container` | `nix build .#kwaainet-container` | `result-kwaainet-container` |
| `make map-server-container` | `nix build .#map-server-container` | `result-map-server-container` |
| `make kwaainet-all-container` | `nix build .#kwaainet-all-container` | `result-kwaainet-all-container` |

> **Note:** Container images use `dockerTools.streamLayeredImage` which is
> Linux-only.  On macOS (Darwin), container packages are not available.

### Tests, checks, and utilities

| Make target | Nix equivalent | Description |
|-------------|---------------|-------------|
| `make check` | `nix flake check` | smoke test + clippy + cargo test |
| `make test` | `nix run .#test-two-node` | two-node integration test |
| — | `nix run .#test-two-node-services` | two-node + map-server integration test |
| — | `nix run .#test-four-node` | four-node integration test |
| — | `nix run .#test-four-node-services` | four-node + map-server integration test |
| `make test-containers` | `nix run .#test-containers` | container image test suite |
| `make test-everything` | — | full suite: check + test + containers + cross + lifecycle |
| `make test-lifecycle-all` | `nix run .#kwaainet-lifecycle-test-all` | all 9 variants × 3 architectures |
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
packages.kwaainet-all-container OCI image — all binaries in one image (Linux only)
packages.test-two-node          two-node integration test script
packages.test-two-node-services two-node + map-server integration test script
packages.test-four-node         four-node integration test script
packages.test-four-node-services four-node + map-server integration test script
packages.test-containers        container image test suite (Linux only)

# Cross-compiled packages (x86_64-linux only):
packages.kwaainet-aarch64-linux-gnu         ARM64 dynamic binary
packages.kwaainet-aarch64-linux-musl        ARM64 static binary
packages.kwaainet-x86_64-linux-musl         x86_64 static binary
packages.map-server-<target>                (same suffixes as above)
packages.p2pd-<target>                      cross-compiled p2pd
packages.*-container-<target>               cross-arch OCI images
packages.test-cross-smoke-<target>          QEMU smoke tests

devShells.default               full dev environment (Rust, Go, protobuf, etc.)

checks.clippy                   workspace-wide clippy (--deny warnings)
checks.cargoTest                workspace-wide cargo test
checks.kwaainet-smoke           sandboxed smoke test (--help, setup, identity)

formatter                       nixfmt
```

## Understanding the Nix environment

### Nix build vs development shell

Nix provides two distinct modes of operation.  Understanding the difference
helps avoid confusion:

**`nix build` (derivation)**:
- Source code is copied into `/nix/store/` (read-only, sandboxed)
- Build happens in a pure, isolated environment (no network, no home dir)
- Output is a deterministic, immutable store path
- Ideal for CI, releases, and reproducible artifacts

**`nix develop` (development shell)**:
- Works with your actual source code in your working directory
- Provides the same toolchain as the build, but in an interactive shell
- You can edit files, run `cargo build`, iterate, and use git normally
- Tools "disappear" when you exit the shell — nothing is installed globally

The `flake.nix` provides both: `nix build .#kwaainet` for the former,
`nix develop` for the latter.

See also: [Development environment with nix-shell](https://nixos.wiki/wiki/Development_environment_with_nix-shell)

### What this repository provides

The Nix setup consists of `flake.nix`, `flake.lock`, and modular files in
`nix/`:

- **`flake.nix`** — main entry point; wires up builds, containers, tests,
  cross-compilation, and the dev shell
- **`flake.lock`** — pins exact versions so all developers use identical inputs
- **`nix/packages.nix`** — shared dependency lists (DRY across build + devshell)
- **`nix/crane.nix`** — two-phase Rust build (cached deps + source)
- **`nix/p2pd.nix`** — go-libp2p-daemon Hivemind fork
- **`nix/proto.nix`** — protobuf codegen derivation
- **`nix/containers.nix`** — OCI container images
- **`nix/cross.nix`** — cross-compilation module
- **`nix/devshell.nix`** — development shell configuration
- **`nix/modules/`** — NixOS service modules (kwaainet, map-server, summit-server)
  with shared security hardening and helper library
- **`nix/k8s-manifests/`** — Kubernetes manifest generation
- **`nix/tests/`** — test infrastructure (smoke, two/four-node, services, containers, cross, microVM lifecycle)
- **`Makefile`** — convenience targets wrapping nix commands

All Nix packages are sourced from [nixpkgs](https://github.com/NixOS/nixpkgs/)
and are searchable at [search.nixos.org](https://search.nixos.org/packages?channel=unstable).

---

## Architecture

```
flake.nix                 orchestrator — wires modules together
Makefile                  build targets with dedicated output symlinks
nix/
  packages.nix            shared dependency lists (DRY across build + devshell)
  p2pd.nix                go-libp2p-daemon Hivemind fork (buildGoModule)
  proto.nix               protobuf codegen derivation (protoc + protoc-gen-prost)
  crane.nix               two-phase Rust build (crane: buildDepsOnly + buildPackage)
  cross.nix               cross-compilation module (reuses crane/p2pd/containers with cross pkgs)
  containers.nix          OCI container images (streamLayeredImage)
  devshell.nix            nix develop environment
  modules/
    default.nix           re-exports all NixOS service modules
    kwaainet.nix          services.kwaainet — P2P inference node
    map-server.nix        services.kwaainet-map-server — HTTP map UI
    summit-server.nix     services.kwaainet-summit-server — WebAuthn + DID
    hardening.nix         shared systemd security baseline
    lib.nix               shared helpers (portFromBindAddr, mkPackageOption)
  k8s-manifests/
    default.nix           entry point — lint, combined output
    namespace.nix         Namespace YAML
    deployment.nix        Deployment YAML (kwaainet + map-server)
    service.nix           ClusterIP Service YAML
    constants.nix         K8s-specific constants
  overlays/
    cross-fixes.nix       overlay to disable broken tests under cross-compilation
    cross-cache.nix       overlay to pin build-host tools to native pkgs (binary cache hits)
    cross-vm.nix          overlay to disable broken tests under QEMU emulation (MicroVMs)
  shell-functions/
    ascii-art.nix         logo display on nix develop entry
  tests/
    default.nix           test orchestration — maps checks + runnable packages
    containers.nix        container image tests (load, size, run)
    cross-smoke.nix       QEMU user-mode smoke test for cross-compiled binaries
    smoke.nix             sandboxed: --help, setup, identity show
    two-node.nix          integration: two kwaainet nodes, distinct identities, port config
    two-node-services.nix integration: two nodes + map-server, health checks
    four-node.nix         integration: four kwaainet nodes, distinct identities, port config
    four-node-services.nix integration: four nodes + map-server, health checks
    microvm/              MicroVM lifecycle testing — 9 variants × 3 architectures (see microvm-testing.md)
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
- **Cross-compilation cache optimization** — `import nixpkgs { crossSystem; }`
  taints all derivation hashes, causing build-host-only tools to miss the
  binary cache.  The `cross-cache.nix` overlay pins these tools to a native
  package set, reducing cross-build overhead from ~235 extra derivations
  (~2.3 GiB from source) to zero — only the actual Rust cross-compilation
  happens locally.
- **Smoke test in sandbox, integration tests outside** — the smoke test verifies
  the binary works without network access (`nix flake check`).  The standalone
  integration tests (two-node, four-node, and their `-services` variants) and
  container tests need runtime resources (localhost networking, container
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

### Cross-compilation (x86_64-linux only)

From an x86_64-linux host, you can cross-compile for four additional targets:

| Target | Suffix | Notes |
|--------|--------|-------|
| `aarch64-unknown-linux-gnu` | `-aarch64-linux-gnu` | ARM64, dynamic (glibc) |
| `aarch64-unknown-linux-musl` | `-aarch64-linux-musl` | ARM64, static |
| `x86_64-unknown-linux-musl` | `-x86_64-linux-musl` | x86_64, static |
| `riscv64gc-unknown-linux-gnu` | `-riscv64-linux-gnu` | RISC-V 64-bit, dynamic (glibc) |

#### How Nix cross-compilation works

Nix handles cross-compilation at the package-set level rather than requiring
per-project toolchain configuration.  The key mechanism is importing nixpkgs
with a `crossSystem`:

```nix
pkgsCross = import nixpkgs {
  localSystem = "x86_64-linux";           # build host
  crossSystem = { config = "aarch64-unknown-linux-gnu"; };  # target
};
```

This produces a complete package set (`pkgsCross`) where every package —
compilers, libraries, build tools — is configured to run on the build host
but produce binaries for the target architecture.  nixpkgs handles the
cross-toolchain setup (GCC/binutils for the target, pkg-config wiring,
sysroot paths) automatically.

KwaaiNet's cross-compilation reuses the same build modules unchanged:

```
flake.nix
  ├─ native build (existing)
  │   └─ crane.nix → kwaainet, map-server
  │
  └─ cross builds (x86_64-linux only)
      └─ nix/cross.nix (for each crossSystem)
          ├─ pkgsNative = import nixpkgs { system; }           ← binary cache hits
          ├─ pkgsCross  = import nixpkgs { localSystem; crossSystem; overlays; }
          │   └─ overlays: cross-fixes.nix + cross-cache.nix { inherit pkgsNative; }
          ├─ crane.nix  (reused — craneLib built from pkgsCross)
          ├─ p2pd.nix   (reused — buildGoModule sets GOOS/GOARCH via pkgsCross)
          └─ containers.nix (reused — streamLayeredImage for target arch, Linux only)
```

Each language toolchain picks up the cross configuration differently:

- **Rust (crane)** — `crane.mkLib pkgsCross` produces a crane library that uses
  the cross Rust toolchain.  `CARGO_BUILD_TARGET` is set to the Rust target
  triple (e.g., `aarch64-unknown-linux-gnu`).  Cargo reads per-target rustflags
  from `core/.cargo/config.toml` automatically (e.g., fp16 flags for aarch64).
- **Go (p2pd)** — `pkgsCross.callPackage ./p2pd.nix {}` invokes `buildGoModule`
  from the cross package set, which automatically sets `GOOS=linux` and
  `GOARCH=arm64` (or the appropriate values).  p2pd uses `CGO_ENABLED=0` so
  there are no C dependencies to cross-compile.
- **OCI containers** — `dockerTools.streamLayeredImage` from `pkgsCross` produces
  images with the correct architecture metadata (e.g., `linux/arm64`).

Two overlays handle cross-compilation concerns:

- **`nix/overlays/cross-fixes.nix`** disables test suites for a few nixpkgs
  packages (`boehmgc`, `libuv`) that fail under cross-compilation because they
  try to execute target-architecture binaries on the build host.
- **`nix/overlays/cross-cache.nix`** pins build-host-only tools to the native
  package set so they hit the binary cache (see next section).

#### Binary cache optimization for cross builds

Importing nixpkgs with a `crossSystem` creates a separate package set where
**every** derivation — including tools that only run on the build host — gets
a different hash from the regular (native) package set.  This means that
build-host-only tools like `remarshal` (used internally by crane for TOML
processing) miss the [cache.nixos.org](https://cache.nixos.org) binary cache
and must be built from source, along with their entire dependency tree.

In practice, this pulled in ~235 unnecessary derivations (~2.3 GiB) including
numpy, via the chain: `remarshal` → `rich-argparse` → `rich` →
`markdown-it-py` → `pytest-regressions` → `numpy`.

The fix is `nix/overlays/cross-cache.nix`, which pins build-host-only tools
to a native package set (`pkgsNative`) created alongside `pkgsCross` in
`cross.nix`.  Since these tools never execute on the target, using the native
(cached) version is safe and correct.

**Result:** cross builds now only compile the 2 Rust-specific derivations
(dependency layer + workspace binary) — everything else is fetched from the
binary cache in seconds.

The overlay is extensible: if other build-host tools are found being rebuilt
from source, add them to the `inherit (pkgsNative) ...` list in
`cross-cache.nix`.

```bash
# Verify: should show only 2 derivations to build
nix build .#kwaainet-aarch64-linux-gnu --dry-run
```

#### What has been tested

All cross-compiled outputs have been built and verified from an x86_64-linux
host:

**Binaries** (4 per target, 16 total):

| Binary | aarch64-gnu | aarch64-musl | x86_64-musl | riscv64-gnu |
|--------|:-----------:|:------------:|:-----------:|:-----------:|
| kwaainet | PASS | PASS | PASS | PASS |
| map-server | PASS | PASS | PASS | PASS |
| p2pd | PASS | PASS | PASS | PASS |

**OCI container images** (3 per target, 12 total):

| Container | aarch64-gnu | aarch64-musl | x86_64-musl | riscv64-gnu |
|-----------|:-----------:|:------------:|:-----------:|:-----------:|
| kwaainet-container | PASS | PASS | PASS | PASS |
| map-server-container | PASS | PASS | PASS | PASS |

**QEMU user-mode smoke tests** (1 per target, 4 total):

| Target | Emulation | `--help` | `--version` |
|--------|-----------|:--------:|:-----------:|
| aarch64-gnu | qemu-aarch64 + glibc sysroot | PASS | PASS |
| aarch64-musl | qemu-aarch64 (static binary) | PASS | PASS |
| x86_64-musl | native (same CPU arch) | PASS | PASS |
| riscv64-gnu | qemu-riscv64 + glibc sysroot | PASS | PASS |

**Binary verification:**

| Target | `file` output | `ldd` output |
|--------|---------------|--------------|
| aarch64-gnu | `ELF 64-bit LSB pie executable, ARM aarch64` | dynamically linked (glibc) |
| aarch64-musl | `ELF 64-bit LSB pie executable, ARM aarch64` | `not a dynamic executable` |
| x86_64-musl | `ELF 64-bit LSB pie executable, x86-64` | musl-linked |
| riscv64-gnu | `ELF 64-bit LSB pie executable, UCB RISC-V` | dynamically linked (glibc) |

**Native regression:** `nix flake check` (clippy + cargo test + smoke test)
passes with no regressions after the cross-compilation changes.

#### Building cross targets

```bash
# Build a single cross target
nix build .#kwaainet-aarch64-linux-gnu
nix build .#kwaainet-aarch64-linux-musl
nix build .#kwaainet-x86_64-linux-musl
nix build .#kwaainet-riscv64-linux-gnu

# Build all binaries for a target (sequential within target)
make cross-aarch64-gnu
make cross-aarch64-musl
make cross-x86_64-musl
make cross-riscv64-gnu

# Build all cross targets in parallel
make -j cross

# Build cross OCI container images
make -j cross-containers

# Verify the binary architecture
file result-kwaainet-aarch64-linux-gnu/bin/kwaainet
# → ELF 64-bit LSB pie executable, ARM aarch64 ...

# Verify static linking (musl targets)
ldd result-kwaainet-aarch64-linux-musl/bin/kwaainet
# → not a dynamic executable
```

#### Cross smoke tests

Cross-compiled binaries are verified using QEMU user-mode emulation.  For
aarch64 targets, `qemu-aarch64` runs the ARM64 binary on the x86_64 host.
For riscv64, `qemu-riscv64` does the same.  For x86_64-musl, no emulation
is needed since it's the same CPU architecture.

Static (musl) binaries run under QEMU without any sysroot — they have no
dynamic library dependencies.  Dynamic (glibc) binaries need the cross libc
as a `QEMU_LD_PREFIX` so the dynamic linker can resolve shared libraries.

```bash
# Run all cross smoke tests
make test-cross

# Or individually
nix build .#test-cross-smoke-aarch64-linux-gnu
nix build .#test-cross-smoke-aarch64-linux-musl
nix build .#test-cross-smoke-x86_64-linux-musl
nix build .#test-cross-smoke-riscv64-linux-gnu
```

#### Limitations

- Cross-compilation is only available from `x86_64-linux` hosts
- Darwin targets (macOS) require Xcode SDK — not supported from Linux
- Windows MSVC targets require the MSVC linker — not supported from Linux
- First cross build compiles the cross toolchain and Rust workspace; subsequent
  builds use the Nix cache.  Build-host tools (Python, remarshal, etc.) are
  fetched from the binary cache via the `cross-cache.nix` overlay

## OCI containers

Each binary is available as a minimal OCI container image built with
`streamLayeredImage`.  Images contain only the binary, CA certificates, and
timezone data — no shell, no coreutils.

```bash
# Build and load a container image
make kwaainet-container
./result-kwaainet-container | docker load    # or: podman load
docker run --rm kwaainet:0.3.27 --help

# Build all containers in parallel
make -j containers

# Run the container test suite (requires podman or docker)
make test-containers
```

Container images are tagged with the workspace version from `core/Cargo.toml`
(e.g., `kwaainet:0.3.27`).

| Container | Exposed port | Contents |
|-----------|-------------|----------|
| `kwaainet` | — | kwaainet binary + bundled p2pd |
| `map-server` | 3030/tcp | map-server binary |
| `kwaainet-all` | 3030/tcp | all binaries (kwaainet + p2pd + map-server) |

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

## MicroVM Lifecycle Testing (Linux only)

Full lifecycle validation of KwaaiNet services running inside NixOS virtual
machines — real systemd, real networking, real service dependencies. No mocks.

Uses [astro/microvm.nix](https://github.com/astro/microvm.nix) for minimal VMs
with shared `/nix/store` via 9P. Supports **three architectures**: x86_64
(KVM), aarch64 (TCG), and riscv64 (TCG) — validating the full stack on every
platform KwaaiNet targets.

Six VM variants cover everything from a single kwaainet node to a full-stack
deployment with PostgreSQL, Docker containers, and Kubernetes manifests.

```bash
# Try it — run the single-node lifecycle test (x86_64)
make test-lifecycle-single-node

# Run on a specific architecture
nix run .#kwaainet-lifecycle-full-test-aarch64-single-node

# Run all variants for one architecture
make test-lifecycle-all-x86_64

# Run all variants on all architectures
make test-lifecycle-all
```

For architecture details, variant descriptions, lifecycle phases, NixOS module
documentation, network setup, and the full file layout, see
**[MicroVM-Based Lifecycle Testing](microvm-testing.md)**.

## Systemd Security Hardening

### Threat model

KwaaiNet is a large distributed P2P inference network — an attractive target for
attack. Nodes run on user hardware (Raspberry Pi, Banana Pi, commodity servers),
making defence-in-depth critical. Each service is sandboxed with systemd security
directives so that even if the process is compromised, the blast radius is
contained: no filesystem writes outside the state directory, no kernel access, no
privilege escalation, and no unnecessary system calls.

### Assessment methodology

We use `systemd-analyze security <service>` inside MicroVM lifecycle tests on all
three architectures (x86_64, aarch64, riscv64). The score is checked automatically
on every test run with a threshold that rejects regressions (`<= 2.5`). The
scoring is done by systemd itself — lower is better, 0.0 is a perfect score.

### What we lock down and why

All directives below are defined in `nix/modules/hardening.nix` and shared by
every KwaaiNet service. Per-service overrides are listed in the next section.

| Category | Directives | Purpose |
|----------|-----------|---------|
| **Filesystem isolation** | `ProtectSystem=strict`, `ProtectHome=true`, `PrivateTmp=true`, `ReadWritePaths` (only state/runtime dirs), `NoExecPaths` (/var, /tmp, /run, /home, /root), `ExecPaths` (/nix/store) | Only the Nix store can execute code; data directories are non-executable. Writes are restricted to the service's state and runtime directories. |
| **Privilege restriction** | `NoNewPrivileges=true`, `CapabilityBoundingSet=[]`, `AmbientCapabilities=""`, `RestrictSUIDSGID=true` | All Linux capabilities are dropped. No SUID/SGID binaries can be executed. |
| **Kernel protection** | `ProtectKernelTunables=true`, `ProtectKernelModules=true`, `ProtectKernelLogs=true`, `ProtectControlGroups=true`, `ProtectHostname=true`, `ProtectClock=true` | Prevents sysctl writes, module loading, dmesg access, cgroup manipulation, hostname changes, and clock adjustments. |
| **Process isolation** | `PrivateDevices=true`, `PrivateIPC=true`, `ProtectProc=invisible`, `ProcSubset=pid`, `LockPersonality=true`, `RestrictNamespaces=true`, `RemoveIPC=true`, `KeyringMode=private` | Hides other processes in /proc, isolates IPC namespaces and kernel keyrings, prevents personality changes and namespace creation. |
| **Memory security** | `MemoryDenyWriteExecute=true`, `SystemCallArchitectures=native` | Prevents W^X violations (JIT, mprotect tricks) and restricts to native syscall ABI only. |
| **System call filtering** | Whitelist `@system-service`; blacklist `~@privileged`, `~@mount`, `~@debug`, `~@module`, `~@reboot`, `~@swap`, `~@clock`, `~@cpu-emulation`, `~@obsolete`, `~@raw-io`, `~@resources` | Only system calls needed for a normal network service are permitted. |
| **Network restriction** | `RestrictAddressFamilies` (AF_INET, AF_INET6, AF_UNIX only), `IPAddressDeny=any` (baseline), `SocketBindAllow`/`SocketBindDeny` (per-service) | Baseline denies all IP traffic; each service explicitly allows only what it needs. Socket binding is restricted to the configured port. |
| **Device policy** | `DevicePolicy=closed`, `DeviceAllow=""` | No device access beyond /dev/null, /dev/zero, /dev/urandom. |
| **Misc** | `NotifyAccess=none`, `UMask=0027`, `RestrictRealtime=true` | Denies sd_notify from any process, restricts file creation permissions, prevents realtime scheduling. |
| **Resource limits** | Per-service slice with `MemoryHigh`, `MemoryMax`, `CPUQuota`, `TasksMax` | Prevents resource exhaustion from affecting the host. |

### Per-service overrides

| Service | Override | Reason |
|---------|---------|--------|
| **kwaainet** | `IPAddressAllow=any`, `SocketBindAllow=tcp:<port> udp:<port>` | P2P node needs unrestricted IP connectivity; binds configured port (default 8080) for TCP and UDP. |
| **map-server** | `IPAddressAllow=any`, `SocketBindAllow=tcp:<port>` | HTTP API; binds configured port (default 3030). |
| **summit-server** | `IPAddressAllow=any`, `SocketBindAllow=tcp:<port>` | HTTP API + PostgreSQL client; binds configured port (default 3000). |

### What we can't lock down and why

| Directive | Why not |
|-----------|---------|
| `PrivateNetwork=true` | Impossible — all services need TCP/UDP for P2P or HTTP. |
| `PrivateUsers=true` | Conflicts with `User=kwaainet` (static system user) and `DynamicUser=true`; breaks file ownership semantics. |
| `RootDirectory`/`RootImage` | Would require a complete chroot. Nix's hermetic `/nix/store` already provides equivalent isolation for executables. |
| `RestrictFileSystems` | Depends on VM filesystem types (9p, ext4, tmpfs); needs careful testing per deployment target. Deferred to a future pass. |
| IP address filtering | Services accept connections from any IP (P2P by design); filtering is handled at the firewall/network level rather than systemd level. |

### Score and verification

The security score is checked automatically in every lifecycle test run. To
verify manually:

```bash
# Run lifecycle test — score is checked automatically (threshold <= 2.5)
nix run .#kwaainet-lifecycle-full-test-x86_64-single-node

# Or check interactively inside a running VM
systemd-analyze security kwaainet
systemd-analyze security kwaainet-map-server
systemd-analyze security kwaainet-summit-server
```

---

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
