# KwaaiNet Nix build targets
#
# Each target writes its output to a dedicated result-<name> symlink,
# so builds don't overwrite each other.
#
# Parallel builds:
#   make -j all          build both binaries in parallel
#   make -j containers   build both OCI containers in parallel

.PHONY: all kwaainet map-server p2pd proto \
        containers kwaainet-container map-server-container \
        check test test-containers fmt develop clean

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

containers: kwaainet-container map-server-container

kwaainet-container:
	nix build .#kwaainet-container -o result-kwaainet-container

map-server-container:
	nix build .#map-server-container -o result-map-server-container

# --- Tests & checks ---

check:
	nix flake check

test:
	nix run .#test-two-node

test-containers:
	nix run .#test-containers

# --- Utilities ---

fmt:
	nix fmt

develop:
	nix develop

clean:
	rm -f result result-kwaainet result-map-server \
	      result-p2pd result-proto \
	      result-kwaainet-container result-map-server-container
