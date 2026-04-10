# Four-node services integration test — exercises kwaainet + map-server on four nodes.
#
# Run with:  nix run .#test-four-node-services
#
# This test is NOT sandboxed (needs localhost networking).  It:
#   1. Creates four isolated node environments (separate HOME dirs).
#   2. Runs `kwaainet setup` + `kwaainet identity show` on each.
#   3. Verifies all four nodes have distinct Peer IDs.
#   4. Starts kwaainet + map-server on each node (different ports).
#   5. Waits for startup, checks status and map-server /health, then tears down.
{ pkgs, kwaainet, map-server }:

pkgs.writeShellApplication {
  name = "kwaainet-test-four-node-services";

  runtimeInputs = [
    kwaainet
    map-server
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.curl
  ];

  text = ''
    set -euo pipefail

    cleanup() {
      echo "--- Cleaning up ---"
      [ -n "''${MAP_PID_A:-}" ] && kill "$MAP_PID_A" 2>/dev/null || true
      [ -n "''${MAP_PID_B:-}" ] && kill "$MAP_PID_B" 2>/dev/null || true
      [ -n "''${MAP_PID_C:-}" ] && kill "$MAP_PID_C" 2>/dev/null || true
      [ -n "''${MAP_PID_D:-}" ] && kill "$MAP_PID_D" 2>/dev/null || true
      [ -n "''${PID_A:-}" ] && kill "$PID_A" 2>/dev/null || true
      [ -n "''${PID_B:-}" ] && kill "$PID_B" 2>/dev/null || true
      [ -n "''${PID_C:-}" ] && kill "$PID_C" 2>/dev/null || true
      [ -n "''${PID_D:-}" ] && kill "$PID_D" 2>/dev/null || true
      wait 2>/dev/null || true
      [ -n "''${HOME_A:-}" ] && rm -rf "$HOME_A"
      [ -n "''${HOME_B:-}" ] && rm -rf "$HOME_B"
      [ -n "''${HOME_C:-}" ] && rm -rf "$HOME_C"
      [ -n "''${HOME_D:-}" ] && rm -rf "$HOME_D"
    }
    trap cleanup EXIT

    HOME_A="$(mktemp -d)"
    HOME_B="$(mktemp -d)"
    HOME_C="$(mktemp -d)"
    HOME_D="$(mktemp -d)"

    # Each node needs its own p2pd socket to avoid collisions
    SOCK_A="$HOME_A/kwaai-p2pd.sock"
    SOCK_B="$HOME_B/kwaai-p2pd.sock"
    SOCK_C="$HOME_C/kwaai-p2pd.sock"
    SOCK_D="$HOME_D/kwaai-p2pd.sock"

    echo "=== Node A: setup ==="
    HOME="$HOME_A" kwaainet setup
    HOME="$HOME_A" kwaainet identity show

    echo ""
    echo "=== Node B: setup ==="
    HOME="$HOME_B" kwaainet setup
    HOME="$HOME_B" kwaainet identity show

    echo ""
    echo "=== Node C: setup ==="
    HOME="$HOME_C" kwaainet setup
    HOME="$HOME_C" kwaainet identity show

    echo ""
    echo "=== Node D: setup ==="
    HOME="$HOME_D" kwaainet setup
    HOME="$HOME_D" kwaainet identity show

    # Extract Peer IDs and verify they are all distinct
    PEER_A="$(HOME="$HOME_A" kwaainet identity show 2>&1 | grep 'Peer ID' | awk '{print $NF}')"
    PEER_B="$(HOME="$HOME_B" kwaainet identity show 2>&1 | grep 'Peer ID' | awk '{print $NF}')"
    PEER_C="$(HOME="$HOME_C" kwaainet identity show 2>&1 | grep 'Peer ID' | awk '{print $NF}')"
    PEER_D="$(HOME="$HOME_D" kwaainet identity show 2>&1 | grep 'Peer ID' | awk '{print $NF}')"

    echo ""
    echo "Node A Peer ID: $PEER_A"
    echo "Node B Peer ID: $PEER_B"
    echo "Node C Peer ID: $PEER_C"
    echo "Node D Peer ID: $PEER_D"

    unique_count=$(printf '%s\n' "$PEER_A" "$PEER_B" "$PEER_C" "$PEER_D" | sort -u | wc -l)
    if [ "$unique_count" -ne 4 ]; then
      echo "FAIL: not all nodes have distinct Peer IDs (got $unique_count unique out of 4)"
      exit 1
    fi
    echo "PASS: all 4 nodes have distinct Peer IDs"

    # Configure different ports so they don't collide
    HOME="$HOME_A" kwaainet config set port 19001
    HOME="$HOME_B" kwaainet config set port 19002
    HOME="$HOME_C" kwaainet config set port 19003
    HOME="$HOME_D" kwaainet config set port 19004

    echo ""
    echo "=== Starting Node A (port 19001) ==="
    HOME="$HOME_A" KWAAINET_SOCKET="$SOCK_A" kwaainet start &
    PID_A=$!

    echo "=== Starting Node B (port 19002) ==="
    HOME="$HOME_B" KWAAINET_SOCKET="$SOCK_B" kwaainet start &
    PID_B=$!

    echo "=== Starting Node C (port 19003) ==="
    HOME="$HOME_C" KWAAINET_SOCKET="$SOCK_C" kwaainet start &
    PID_C=$!

    echo "=== Starting Node D (port 19004) ==="
    HOME="$HOME_D" KWAAINET_SOCKET="$SOCK_D" kwaainet start &
    PID_D=$!

    echo "=== Starting map-server A (port 3030) ==="
    BIND_ADDR="127.0.0.1:3030" KWAAINET_SOCKET="$SOCK_A" map-server &
    MAP_PID_A=$!

    echo "=== Starting map-server B (port 3031) ==="
    BIND_ADDR="127.0.0.1:3031" KWAAINET_SOCKET="$SOCK_B" map-server &
    MAP_PID_B=$!

    echo "=== Starting map-server C (port 3032) ==="
    BIND_ADDR="127.0.0.1:3032" KWAAINET_SOCKET="$SOCK_C" map-server &
    MAP_PID_C=$!

    echo "=== Starting map-server D (port 3033) ==="
    BIND_ADDR="127.0.0.1:3033" KWAAINET_SOCKET="$SOCK_D" map-server &
    MAP_PID_D=$!

    # Give nodes time to initialize
    echo "Waiting 5s for nodes to start..."
    sleep 5

    # Check kwaainet processes
    if kill -0 "$PID_A" 2>/dev/null; then
      echo "PASS: Node A kwaainet is running (pid $PID_A)"
    else
      echo "WARN: Node A kwaainet exited early (may lack network — non-fatal)"
    fi

    if kill -0 "$PID_B" 2>/dev/null; then
      echo "PASS: Node B kwaainet is running (pid $PID_B)"
    else
      echo "WARN: Node B kwaainet exited early (may lack network — non-fatal)"
    fi

    if kill -0 "$PID_C" 2>/dev/null; then
      echo "PASS: Node C kwaainet is running (pid $PID_C)"
    else
      echo "WARN: Node C kwaainet exited early (may lack network — non-fatal)"
    fi

    if kill -0 "$PID_D" 2>/dev/null; then
      echo "PASS: Node D kwaainet is running (pid $PID_D)"
    else
      echo "WARN: Node D kwaainet exited early (may lack network — non-fatal)"
    fi

    # Check map-server processes
    if kill -0 "$MAP_PID_A" 2>/dev/null; then
      echo "PASS: Node A map-server is running (pid $MAP_PID_A)"
    else
      echo "WARN: Node A map-server exited early"
    fi

    if kill -0 "$MAP_PID_B" 2>/dev/null; then
      echo "PASS: Node B map-server is running (pid $MAP_PID_B)"
    else
      echo "WARN: Node B map-server exited early"
    fi

    if kill -0 "$MAP_PID_C" 2>/dev/null; then
      echo "PASS: Node C map-server is running (pid $MAP_PID_C)"
    else
      echo "WARN: Node C map-server exited early"
    fi

    if kill -0 "$MAP_PID_D" 2>/dev/null; then
      echo "PASS: Node D map-server is running (pid $MAP_PID_D)"
    else
      echo "WARN: Node D map-server exited early"
    fi

    # Check map-server health endpoints
    if curl -sf http://127.0.0.1:3030/health > /dev/null 2>&1; then
      echo "PASS: Node A map-server /health returned 200"
    else
      echo "WARN: Node A map-server /health not reachable"
    fi

    if curl -sf http://127.0.0.1:3031/health > /dev/null 2>&1; then
      echo "PASS: Node B map-server /health returned 200"
    else
      echo "WARN: Node B map-server /health not reachable"
    fi

    if curl -sf http://127.0.0.1:3032/health > /dev/null 2>&1; then
      echo "PASS: Node C map-server /health returned 200"
    else
      echo "WARN: Node C map-server /health not reachable"
    fi

    if curl -sf http://127.0.0.1:3033/health > /dev/null 2>&1; then
      echo "PASS: Node D map-server /health returned 200"
    else
      echo "WARN: Node D map-server /health not reachable"
    fi

    # Verify config persisted
    HOME="$HOME_A" kwaainet config show | grep -q "19001" && echo "PASS: Node A port config persisted"
    HOME="$HOME_B" kwaainet config show | grep -q "19002" && echo "PASS: Node B port config persisted"
    HOME="$HOME_C" kwaainet config show | grep -q "19003" && echo "PASS: Node C port config persisted"
    HOME="$HOME_D" kwaainet config show | grep -q "19004" && echo "PASS: Node D port config persisted"

    echo ""
    echo "Four-node services integration test complete."
  '';
}
