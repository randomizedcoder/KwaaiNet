# Script generators for KwaaiNet MicroVM lifecycle testing.
# Provides bash helper functions interpolated into test scripts.
#
{ pkgs, lib }:
let
  constants = import ../constants.nix;

  # Common runtime inputs for all lifecycle scripts
  commonInputs = with pkgs; [
    coreutils
    gnugrep
    gnused
    gawk
    procps
    netcat-openbsd
    bc
    util-linux
  ];

  # SSH-related inputs
  sshInputs = with pkgs; [
    openssh
    sshpass
  ];

  # ANSI color helpers (shell functions)
  colorHelpers = ''
    _reset='\033[0m'
    _bold='\033[1m'
    _red='\033[31m'
    _green='\033[32m'
    _yellow='\033[33m'
    _blue='\033[34m'
    _cyan='\033[36m'

    info() { echo -e "''${_cyan}$*''${_reset}"; }
    success() { echo -e "''${_green}$*''${_reset}"; }
    warn() { echo -e "''${_yellow}$*''${_reset}"; }
    error() { echo -e "''${_red}$*''${_reset}"; }
    bold() { echo -e "''${_bold}$*''${_reset}"; }

    phase_header() {
      local phase="$1"
      local name="$2"
      local timeout="$3"
      echo ""
      echo -e "''${_bold}--- Phase $phase: $name (timeout: ''${timeout}s) ---''${_reset}"
    }

    result_pass() {
      local msg="$1"
      local time_ms="$2"
      echo -e "  ''${_green}PASS''${_reset}: $msg (''${time_ms}ms)"
    }

    result_fail() {
      local msg="$1"
      local time_ms="$2"
      echo -e "  ''${_red}FAIL''${_reset}: $msg (''${time_ms}ms)"
    }

    result_skip() {
      local msg="$1"
      echo -e "  ''${_yellow}SKIP''${_reset}: $msg"
    }
  '';

  # Timing helpers
  timingHelpers = ''
    time_ms() {
      echo $(($(date +%s%N) / 1000000))
    }

    elapsed_ms() {
      local start="$1"
      local now
      now=$(time_ms)
      echo $((now - start))
    }

    format_ms() {
      local ms="$1"
      if [[ $ms -lt 1000 ]]; then
        echo "''${ms}ms"
      elif [[ $ms -lt 60000 ]]; then
        echo "$((ms / 1000)).$((ms % 1000 / 100))s"
      else
        local mins=$((ms / 60000))
        local secs=$(((ms % 60000) / 1000))
        echo "''${mins}m''${secs}s"
      fi
    }
  '';

  # Process detection helpers
  processHelpers = ''
    vm_is_running() {
      local hostname="$1"
      pgrep -f "process=$hostname" >/dev/null 2>&1
    }

    vm_pid() {
      local hostname="$1"
      pgrep -f "process=$hostname" 2>/dev/null | head -1
    }

    wait_for_process() {
      local hostname="$1"
      local timeout="$2"
      local elapsed=0
      while [[ $elapsed -lt $timeout ]]; do
        if vm_is_running "$hostname"; then
          return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
      done
      return 1
    }

    wait_for_exit() {
      local hostname="$1"
      local timeout="$2"
      local elapsed=0
      while [[ $elapsed -lt $timeout ]]; do
        if ! vm_is_running "$hostname"; then
          return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
      done
      return 1
    }

    kill_vm() {
      local hostname="$1"
      local pid
      pid=$(vm_pid "$hostname")
      if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null || true
        sleep 1
        if vm_is_running "$hostname"; then
          kill -9 "$pid" 2>/dev/null || true
        fi
      fi
    }
  '';

  # Console connection helpers
  consoleHelpers = ''
    port_is_open() {
      local host="$1"
      local port="$2"
      nc -z "$host" "$port" 2>/dev/null
    }

    wait_for_console() {
      local port="$1"
      local timeout="$2"
      local elapsed=0
      while [[ $elapsed -lt $timeout ]]; do
        if port_is_open "127.0.0.1" "$port"; then
          return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
      done
      return 1
    }
  '';

  # SSH helpers generator
  mkSshHelpers =
    { sshPassword }:
    let
      sshOpts = lib.concatStringsSep " " [
        "-o StrictHostKeyChecking=no"
        "-o UserKnownHostsFile=/dev/null"
        "-o ConnectTimeout=5"
        "-o LogLevel=ERROR"
        "-o PubkeyAuthentication=no"
      ];
    in
    ''
      ssh_cmd() {
        local host="$1"
        local port="$2"
        shift 2
        sshpass -p ${sshPassword} ssh ${sshOpts} -p "$port" "root@$host" "$@" 2>/dev/null
      }

      check_service() {
        local host="$1"
        local port="$2"
        local service="$3"
        ssh_cmd "$host" "$port" "systemctl is-active $service" 2>/dev/null | grep -q "^active$"
      }

      wait_for_service() {
        local host="$1"
        local port="$2"
        local service="$3"
        local timeout="$4"
        local elapsed=0
        while [[ $elapsed -lt $timeout ]]; do
          local status
          status=$(ssh_cmd "$host" "$port" "systemctl is-active $service" 2>/dev/null || echo "unknown")
          case "$status" in
            active) return 0 ;;
            failed) return 1 ;;
            *) sleep 1; elapsed=$((elapsed + 1)) ;;
          esac
        done
        return 1
      }

      wait_for_ssh() {
        local host="$1"
        local port="$2"
        local timeout="$3"
        local elapsed=0
        while [[ $elapsed -lt $timeout ]]; do
          if sshpass -p ${sshPassword} ssh ${sshOpts} -p "$port" "root@$host" true 2>/dev/null; then
            return 0
          fi
          sleep 1
          elapsed=$((elapsed + 1))
        done
        return 1
      }
    '';

  # Journal polling — grep a systemd unit's log for a pattern
  journalHelpers = ''
    wait_for_journal_entry() {
      local host="$1"
      local port="$2"
      local unit="$3"
      local pattern="$4"
      local timeout="$5"
      local elapsed=0
      while [[ $elapsed -lt $timeout ]]; do
        if ssh_cmd "$host" "$port" "journalctl -u $unit --no-pager -q 2>/dev/null" | grep -q "$pattern"; then
          return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
      done
      return 1
    }
  '';

  # HTTP body retrieval (not just status code)
  httpBodyHelpers = ''
    ssh_curl_body() {
      local host="$1"
      local port="$2"
      local url="$3"
      ssh_cmd "$host" "$port" "curl -sf '$url' 2>/dev/null" || echo ""
    }
  '';

  # Peer identity helpers
  peerHelpers = ''
    extract_peer_id() {
      local host="$1"
      local port="$2"
      # Prefer the journal — the Peer ID is logged at startup as
      # "Peer ID: 12D3Koo..." and doesn't require running the CLI
      # (which takes ~25s for full initialisation under the wrong HOME).
      local pid
      pid=$(ssh_cmd "$host" "$port" "journalctl -u kwaainet --no-pager -q 2>/dev/null | grep -oP 'Peer ID:\\s+\\K\\S+' | tail -1" || echo "")
      if [[ -n "$pid" ]]; then
        echo "$pid"
      else
        # Fallback: run CLI with correct HOME
        ssh_cmd "$host" "$port" "HOME=/var/lib/kwaainet kwaainet identity show 2>/dev/null | grep -oP 'Peer ID:\\s+\\K\\S+'" || echo ""
      fi
    }

    build_multiaddr() {
      local ip="$1"
      local p2p_port="$2"
      local peer_id="$3"
      echo "/ip6/$ip/tcp/$p2p_port/p2p/$peer_id"
    }

    inject_bootstrap_peer() {
      local host="$1"
      local port="$2"
      local multiaddr="$3"
      # The kwaainet service runs as user kwaainet with HOME=/var/lib/kwaainet.
      # Config lives at /var/lib/kwaainet/.kwaainet/config.yaml (created by
      # ExecStartPre = kwaainet setup).
      # Use `kwaainet config set` with correct HOME to update initial_peers,
      # then restart the service to pick up the new bootstrap peer.
      ssh_cmd "$host" "$port" "
        HOME=/var/lib/kwaainet kwaainet config set initial_peers '$multiaddr'
        systemctl restart kwaainet
      "
    }
  '';

  # TAP bridge availability check
  tapHelpers = ''
    check_tap_available() {
      ip link show ${constants.network.bridge} >/dev/null 2>&1
    }
  '';

in
{
  inherit
    constants
    commonInputs
    sshInputs
    colorHelpers
    timingHelpers
    processHelpers
    consoleHelpers
    mkSshHelpers
    journalHelpers
    httpBodyHelpers
    peerHelpers
    tapHelpers
    ;
}
