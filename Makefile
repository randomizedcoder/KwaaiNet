# KwaaiNet Nix build targets
#
# Each target writes its output to a dedicated result-<name> symlink,
# so builds don't overwrite each other.
#
# Parallel builds:
#   make -j all          build both binaries in parallel
#   make -j containers   build both OCI containers in parallel
#   make -j cross        cross-compile all targets in parallel
#   make -j all containers cross   build everything in parallel

.PHONY: all kwaainet map-server p2pd proto \
        containers kwaainet-container map-server-container kwaainet-all-container \
        cross cross-aarch64-gnu cross-aarch64-musl cross-x86_64-musl cross-riscv64-gnu \
        cross-containers cross-containers-aarch64-gnu cross-containers-aarch64-musl cross-containers-x86_64-musl cross-containers-riscv64-gnu \
        check test test-containers test-cross \
        test-lifecycle-all test-lifecycle-all-x86_64 test-lifecycle-all-aarch64 test-lifecycle-all-riscv64 \
        test-everything \
        network-setup network-teardown k8s-manifests \
        fmt develop clean

all: kwaainet map-server

# --- Binaries ---

kwaainet:
	nix build .#kwaainet -o result-kwaainet

map-server:
	nix build .#map-server -o result-map-server

p2pd:
	nix build .#p2pd -o result-p2pd

proto:
	nix build .#protoRs -o result-proto

# --- OCI Containers (Linux only) ---

containers: kwaainet-container map-server-container kwaainet-all-container

kwaainet-container:
	nix build .#kwaainet-container -o result-kwaainet-container

map-server-container:
	nix build .#map-server-container -o result-map-server-container

kwaainet-all-container:
	nix build .#kwaainet-all-container -o result-kwaainet-all-container

# --- Cross-compilation (x86_64-linux only) ---

cross: cross-aarch64-gnu cross-aarch64-musl cross-x86_64-musl cross-riscv64-gnu

cross-aarch64-gnu:
	nix build .#kwaainet-aarch64-linux-gnu -o result-kwaainet-aarch64-linux-gnu
	nix build .#map-server-aarch64-linux-gnu -o result-map-server-aarch64-linux-gnu
	nix build .#p2pd-aarch64-linux-gnu -o result-p2pd-aarch64-linux-gnu

cross-aarch64-musl:
	nix build .#kwaainet-aarch64-linux-musl -o result-kwaainet-aarch64-linux-musl
	nix build .#map-server-aarch64-linux-musl -o result-map-server-aarch64-linux-musl
	nix build .#p2pd-aarch64-linux-musl -o result-p2pd-aarch64-linux-musl

cross-x86_64-musl:
	nix build .#kwaainet-x86_64-linux-musl -o result-kwaainet-x86_64-linux-musl
	nix build .#map-server-x86_64-linux-musl -o result-map-server-x86_64-linux-musl
	nix build .#p2pd-x86_64-linux-musl -o result-p2pd-x86_64-linux-musl

cross-riscv64-gnu:
	nix build .#kwaainet-riscv64-linux-gnu -o result-kwaainet-riscv64-linux-gnu
	nix build .#map-server-riscv64-linux-gnu -o result-map-server-riscv64-linux-gnu
	nix build .#p2pd-riscv64-linux-gnu -o result-p2pd-riscv64-linux-gnu

# --- Cross OCI Containers ---

cross-containers: cross-containers-aarch64-gnu cross-containers-aarch64-musl cross-containers-x86_64-musl cross-containers-riscv64-gnu

cross-containers-aarch64-gnu:
	nix build .#kwaainet-container-aarch64-linux-gnu -o result-kwaainet-container-aarch64-linux-gnu
	nix build .#map-server-container-aarch64-linux-gnu -o result-map-server-container-aarch64-linux-gnu
	nix build .#kwaainet-all-container-aarch64-linux-gnu -o result-kwaainet-all-container-aarch64-linux-gnu

cross-containers-aarch64-musl:
	nix build .#kwaainet-container-aarch64-linux-musl -o result-kwaainet-container-aarch64-linux-musl
	nix build .#map-server-container-aarch64-linux-musl -o result-map-server-container-aarch64-linux-musl
	nix build .#kwaainet-all-container-aarch64-linux-musl -o result-kwaainet-all-container-aarch64-linux-musl

cross-containers-x86_64-musl:
	nix build .#kwaainet-container-x86_64-linux-musl -o result-kwaainet-container-x86_64-linux-musl
	nix build .#map-server-container-x86_64-linux-musl -o result-map-server-container-x86_64-linux-musl
	nix build .#kwaainet-all-container-x86_64-linux-musl -o result-kwaainet-all-container-x86_64-linux-musl

cross-containers-riscv64-gnu:
	nix build .#kwaainet-container-riscv64-linux-gnu -o result-kwaainet-container-riscv64-linux-gnu
	nix build .#map-server-container-riscv64-linux-gnu -o result-map-server-container-riscv64-linux-gnu
	nix build .#kwaainet-all-container-riscv64-linux-gnu -o result-kwaainet-all-container-riscv64-linux-gnu

# --- Tests & checks ---

check:
	nix flake check

test:
	nix run .#test-two-node

test-containers:
	nix run .#test-containers

test-cross:
	nix build .#test-cross-smoke-aarch64-linux-gnu -o result-test-cross-aarch64-gnu
	nix build .#test-cross-smoke-aarch64-linux-musl -o result-test-cross-aarch64-musl
	nix build .#test-cross-smoke-x86_64-linux-musl -o result-test-cross-x86_64-musl
	nix build .#test-cross-smoke-riscv64-linux-gnu -o result-test-cross-riscv64-gnu

# --- MicroVM Lifecycle Tests (Linux only) ---
# Supports per-architecture tests: test-lifecycle-<variant>-<arch>
# Default (no arch suffix) uses x86_64.

test-lifecycle-%:
	nix run .#kwaainet-lifecycle-full-test-$*

test-lifecycle-all:
	nix run .#kwaainet-lifecycle-test-all

# Per-architecture test suites
test-lifecycle-all-x86_64:
	nix run .#kwaainet-lifecycle-test-all -- --arch=x86_64

test-lifecycle-all-aarch64:
	nix run .#kwaainet-lifecycle-test-all -- --arch=aarch64

test-lifecycle-all-riscv64:
	nix run .#kwaainet-lifecycle-test-all -- --arch=riscv64

# --- Run all tests in series ---
# Runs: flake check → two-node → containers → cross smoke → lifecycle (all x86_64)
# Handles TAP network setup/teardown automatically (requires sudo).

test-everything:
	@echo "══════════════════════════════════════"
	@echo "  KwaaiNet — Full Test Suite"
	@echo "══════════════════════════════════════"
	@echo ""
	@echo "▸ [1/6] nix flake check (clippy + cargo test + smoke)"
	nix flake check
	@echo ""
	@echo "▸ [2/6] Two-node localhost integration"
	nix run .#test-two-node
	@echo ""
	@echo "▸ [3/6] OCI container validation"
	nix run .#test-containers
	@echo ""
	@echo "▸ [4/6] Cross-compilation smoke tests"
	nix build .#test-cross-smoke-aarch64-linux-gnu -o result-test-cross-aarch64-gnu
	nix build .#test-cross-smoke-aarch64-linux-musl -o result-test-cross-aarch64-musl
	nix build .#test-cross-smoke-x86_64-linux-musl -o result-test-cross-x86_64-musl
	nix build .#test-cross-smoke-riscv64-linux-gnu -o result-test-cross-riscv64-gnu
	@echo ""
	@echo "▸ [5/6] TAP network setup (sudo)"
	@if ip link show kwaaibr0 >/dev/null 2>&1; then \
		echo "  TAP network already up — skipping setup"; \
	else \
		sudo nix run .#kwaainet-network-setup; \
	fi
	@echo ""
	@echo "▸ [6/6] MicroVM lifecycle tests (x86_64, all 8 variants)"
	nix run .#kwaainet-lifecycle-test-all -- --arch=x86_64
	@echo ""
	@echo "▸ Teardown TAP network"
	@if ip link show kwaaibr0 >/dev/null 2>&1; then \
		sudo -n nix run .#kwaainet-network-teardown 2>/dev/null || \
		echo "  WARN: sudo expired — run manually: sudo nix run .#kwaainet-network-teardown"; \
	fi
	@echo ""
	@echo "══════════════════════════════════════"
	@echo "  All tests passed!"
	@echo "══════════════════════════════════════"

network-setup:
	sudo nix run .#kwaainet-network-setup

network-teardown:
	sudo nix run .#kwaainet-network-teardown

k8s-manifests:
	nix build .#kwaainet-k8s-manifests -o result-k8s-manifests

# --- Utilities ---

fmt:
	nix fmt

develop:
	nix develop

clean:
	rm -f result result-kwaainet result-map-server \
	      result-p2pd result-proto \
	      result-kwaainet-container result-map-server-container result-kwaainet-all-container \
	      result-summit-server-container result-k8s-manifests \
	      result-kwaainet-aarch64-linux-gnu result-map-server-aarch64-linux-gnu result-p2pd-aarch64-linux-gnu \
	      result-kwaainet-aarch64-linux-musl result-map-server-aarch64-linux-musl result-p2pd-aarch64-linux-musl \
	      result-kwaainet-x86_64-linux-musl result-map-server-x86_64-linux-musl result-p2pd-x86_64-linux-musl \
	      result-kwaainet-riscv64-linux-gnu result-map-server-riscv64-linux-gnu result-p2pd-riscv64-linux-gnu \
	      result-kwaainet-container-aarch64-linux-gnu result-map-server-container-aarch64-linux-gnu result-kwaainet-all-container-aarch64-linux-gnu \
	      result-kwaainet-container-aarch64-linux-musl result-map-server-container-aarch64-linux-musl result-kwaainet-all-container-aarch64-linux-musl \
	      result-kwaainet-container-x86_64-linux-musl result-map-server-container-x86_64-linux-musl result-kwaainet-all-container-x86_64-linux-musl \
	      result-kwaainet-container-riscv64-linux-gnu result-map-server-container-riscv64-linux-gnu result-kwaainet-all-container-riscv64-linux-gnu \
	      result-test-cross-aarch64-gnu result-test-cross-aarch64-musl result-test-cross-x86_64-musl result-test-cross-riscv64-gnu \
	      result-vm result-microvm-* result-lifecycle-* \
	      result-cross-aarch64-gnu-all result-cross-aarch64-gnu-all-* \
	      result-[0-9] result-[0-9][0-9]
