# Development shell — provides the full toolchain for hacking on KwaaiNet.
{ pkgs, packages }:

let
  asciiArt = import ./shell-functions/ascii-art.nix { };

  helpScript = pkgs.writeShellScriptBin "kwaainet-help" ''
    cat <<'HELP'

  ╔══════════════════════════════════════════════════════════════════╗
  ║                 KwaaiNet Developer Reference                     ║
  ╚══════════════════════════════════════════════════════════════════╝

  BUILDING
  ────────
    cargo build              Build kwaainet from core/ (incremental)
    cargo build --release    Build optimized binary
    cargo test --all         Run all unit tests
    nix build                Build kwaainet via Nix (reproducible)
    nix build .#kwaainet     Build kwaainet package
    nix build .#map-server   Build map-server package
    nix build .#p2pd         Build go-libp2p-daemon
    nix build .#protoRs      Build protobuf codegen

  MAKEFILE TARGETS (recommended — uses dedicated output symlinks)
  ────────────────
    make                     Build kwaainet + map-server
    make kwaainet            Build kwaainet     → result-kwaainet/
    make map-server          Build map-server   → result-map-server/
    make p2pd                Build p2pd         → result-p2pd/
    make proto               Build proto codegen → result-proto/
    make containers          Build all OCI containers (Linux)
    make clean               Remove all result-* symlinks

  TESTING
  ───────
    make check               Smoke test + clippy + cargo test
    make test                Two-node integration test
    make test-containers     Container image tests (needs podman/docker)
    make test-everything     Full suite: check + test + containers + cross + lifecycle
    nix flake check          Same as 'make check'
    nix run .#test-two-node  Two-node integration test

  MICROVM LIFECYCLE TESTS (Linux only, requires KVM)
  ──────────────────────
    make test-lifecycle-single-node       Single-node lifecycle test (x86_64)
    make test-lifecycle-all-x86_64        All variants for x86_64
    make test-lifecycle-all               All variants × all architectures
    nix run .#kwaainet-lifecycle-test-all Run every lifecycle variant

  CROSS-COMPILATION (x86_64-linux only)
  ─────────────────
    make cross               Build all cross targets in parallel
    make cross-aarch64-gnu   ARM64 dynamic (glibc)
    make cross-aarch64-musl  ARM64 static (musl)
    make cross-x86_64-musl   x86_64 static (musl)
    make cross-riscv64-gnu   RISC-V 64-bit dynamic
    make test-cross           QEMU smoke tests for cross binaries

  FORMATTING & LINTING
  ────────────────────
    nix fmt                  Format all Nix files
    cargo fmt                Format Rust code
    cargo clippy             Run Rust linter

  DEPENDENCY UPDATES
  ──────────────────
    nix flake update         Update all flake inputs
    nix flake update nixpkgs Update nixpkgs only
    cd core && cargo update  Update Rust dependencies

  KEY FILES
  ─────────
    flake.nix                Main entry point
    nix/README.md            Full Nix documentation
    nix/packages.nix         Shared dependency definitions
    nix/crane.nix            Rust build (crane two-phase)
    nix/devshell.nix         This dev shell configuration
    nix/tests/               Test infrastructure
    nix/modules/             NixOS service modules
    Makefile                 Convenience build targets

  TIPS
  ────
    • First build downloads all deps — subsequent builds use the Nix cache
    • 'nix develop' tools disappear when you exit — nothing installed globally
    • Use 'make -j' for parallel builds
    • See nix/README.md for architecture details and design decisions

HELP
  '';
in
pkgs.mkShell {
  name = "kwaainet-dev";

  nativeBuildInputs = packages.nativeBuildInputs ++ packages.devTools ++ [ helpScript ];

  inherit (packages) buildInputs;

  RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";

  shellHook = ''
    ${asciiArt}
    echo ""
    echo "  Type 'kwaainet-help' for a full command reference."
    echo ""
  '';
}
