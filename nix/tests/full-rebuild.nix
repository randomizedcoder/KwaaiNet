# Full rebuild & test suite — recovers from mid-build crash.
#
# Run with:  nix run .#full-rebuild
#
# Phases:
#   1. Native binaries (kwaainet + map-server)
#   1.5. Flake check (clippy + cargo test + smoke)
#   2. Native containers (3 OCI images)
#   3. Cross-compilation (sequential to avoid resource exhaustion)
#   4. Integration tests (two-node + container validation)
#   5. MicroVM lifecycle tests — x86_64 (KVM, fast)
#   6. MicroVM lifecycle tests — cross-architecture (TCG, slow)
#   7. Final verification
{ pkgs }:

pkgs.writeShellApplication {
  name = "kwaainet-full-rebuild";

  runtimeInputs = [
    pkgs.coreutils
    pkgs.gnumake
    pkgs.nix
    pkgs.gnugrep
  ];

  text = ''
    set -euo pipefail

    # Must run from repo root
    if [ ! -f flake.nix ]; then
      echo "ERROR: Run from the KwaaiNet repo root"
      exit 1
    fi

    pass() { echo -e "\n==> PASS: $1\n"; }
    fail() { echo -e "\n==> FAIL: $1\n"; exit 1; }
    phase() { echo -e "\n===================================="; echo "  Phase $1: $2"; echo "===================================="; }

    # --- Phase 1: Native binaries ---
    phase 1 "Native binaries"
    make -j all || fail "Native build failed"
    pass "Native binaries (kwaainet + map-server)"

    # --- Phase 1.5: Flake check ---
    phase 1.5 "Flake check (clippy + cargo test + smoke)"
    make check || fail "Flake check failed"
    pass "Flake check"

    # --- Phase 2: Native containers ---
    phase 2 "Native containers"
    make -j containers || fail "Container build failed"
    pass "Native containers (3 OCI images)"

    # --- Phase 3: Cross-compilation (sequential to avoid crash repeat) ---
    phase 3 "Cross-compilation (sequential)"

    for target in x86_64-musl aarch64-gnu aarch64-musl riscv64-gnu; do
      echo "--- cross-$target ---"
      make "cross-$target" || fail "cross-$target failed"
      pass "cross-$target"
    done

    echo "--- QEMU smoke tests ---"
    make test-cross || fail "Cross smoke tests failed"
    pass "Cross smoke tests"

    echo "--- Cross containers ---"
    for target in x86_64-musl aarch64-gnu aarch64-musl riscv64-gnu; do
      make "cross-containers-$target" || fail "cross-containers-$target failed"
    done
    pass "All cross containers"

    # --- Phase 4: Integration tests ---
    phase 4 "Integration tests"
    make test || fail "Two-node integration test failed"
    make test-containers || fail "Container tests failed"
    pass "Integration tests"

    # --- Phase 5: MicroVM lifecycle tests — x86_64 (KVM) ---
    phase 5 "MicroVM lifecycle tests — x86_64"

    for variant in single-node map-server full-stack docker k8s; do
      echo "--- x86_64-$variant ---"
      nix run ".#kwaainet-lifecycle-full-test-x86_64-$variant" || fail "x86_64-$variant failed"
      pass "x86_64-$variant"
    done

    echo "--- Setting up network for two-node tests ---"
    sudo nix run .#kwaainet-network-setup || fail "Network setup failed"

    for variant in two-node two-node-services; do
      echo "--- x86_64-$variant ---"
      nix run ".#kwaainet-lifecycle-full-test-x86_64-$variant" || fail "x86_64-$variant failed"
      pass "x86_64-$variant"
    done
    pass "All x86_64 lifecycle tests (7/7)"

    # --- Phase 6: MicroVM lifecycle tests — cross-architecture (TCG) ---
    phase 6 "MicroVM lifecycle tests — cross-architecture (TCG, slow)"

    echo "--- aarch64 (2x timeout scaling) ---"
    make test-lifecycle-all-aarch64 || fail "aarch64 lifecycle tests failed"
    pass "aarch64 lifecycle tests"

    echo "--- riscv64 (3x timeout scaling) ---"
    make test-lifecycle-all-riscv64 || fail "riscv64 lifecycle tests failed"
    pass "riscv64 lifecycle tests"

    echo "--- Tearing down network ---"
    sudo nix run .#kwaainet-network-teardown || echo "WARN: Network teardown skipped"

    pass "All cross-arch lifecycle tests"

    # --- Phase 7: Final verification ---
    phase 7 "Final verification"

    echo "Checking result symlinks contain v0.3.27..."
    for link in result-kwaainet result-map-server; do
      if [ ! -L "$link" ]; then
        fail "$link symlink missing"
      fi
      target="$(readlink "$link")"
      if [[ "$target" != *"0.3.27"* ]]; then
        fail "$link points to $target (expected v0.3.27)"
      fi
    done
    pass "Version check — all v0.3.27"

    echo ""
    echo "============================================"
    echo "  ALL PHASES COMPLETE"
    echo "============================================"
    echo ""
    echo "Result symlinks:"
    find . -maxdepth 1 -name 'result-*' -type l -printf '%f -> %l\n' | sort | head -40
  '';
}
