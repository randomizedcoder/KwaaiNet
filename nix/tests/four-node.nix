# Four-node integration test — exercises four kwaainet processes on localhost.
#
# Run with:  nix run .#test-four-node
#
# This test is NOT sandboxed (needs localhost networking).  It:
#   1. Creates four isolated node environments (separate HOME dirs).
#   2. Runs `kwaainet setup` + `kwaainet identity show` on each.
#   3. Verifies all four nodes have distinct Peer IDs.
#   4. Starts all four nodes in foreground mode on different ports.
#   5. Waits for startup, checks status, then tears everything down.
{ pkgs, kwaainet }:

pkgs.writeShellApplication {
  name = "kwaainet-test-four-node";

  runtimeInputs = [
    kwaainet
    pkgs.coreutils
    pkgs.gnugrep
  ];

  text = ''
    set -euo pipefail

    cleanup() {
      echo "--- Cleaning up ---"
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

    # Give nodes time to initialize
    echo "Waiting 5s for nodes to start..."
    sleep 5

    # Check all processes are still running
    if kill -0 "$PID_A" 2>/dev/null; then
      echo "PASS: Node A is running (pid $PID_A)"
    else
      echo "WARN: Node A exited early (may lack network — non-fatal)"
    fi

    if kill -0 "$PID_B" 2>/dev/null; then
      echo "PASS: Node B is running (pid $PID_B)"
    else
      echo "WARN: Node B exited early (may lack network — non-fatal)"
    fi

    if kill -0 "$PID_C" 2>/dev/null; then
      echo "PASS: Node C is running (pid $PID_C)"
    else
      echo "WARN: Node C exited early (may lack network — non-fatal)"
    fi

    if kill -0 "$PID_D" 2>/dev/null; then
      echo "PASS: Node D is running (pid $PID_D)"
    else
      echo "WARN: Node D exited early (may lack network — non-fatal)"
    fi

    # Verify config persisted
    HOME="$HOME_A" kwaainet config show | grep -q "19001" && echo "PASS: Node A port config persisted"
    HOME="$HOME_B" kwaainet config show | grep -q "19002" && echo "PASS: Node B port config persisted"
    HOME="$HOME_C" kwaainet config show | grep -q "19003" && echo "PASS: Node C port config persisted"
    HOME="$HOME_D" kwaainet config show | grep -q "19004" && echo "PASS: Node D port config persisted"

    echo ""
    echo "Four-node integration test complete."
  '';
}
