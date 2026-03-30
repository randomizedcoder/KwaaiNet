# Entry point for KwaaiNet MicroVM lifecycle testing.
# Generates lifecycle test scripts for all MicroVM variants across architectures.
#
# Generated outputs:
#   kwaainet-lifecycle-full-test-<arch>-<variant>  - Full lifecycle test per arch+variant
#   kwaainet-lifecycle-full-test-<variant>          - Backwards-compat alias (x86_64)
#   kwaainet-lifecycle-test-all                    - Test all variants sequentially
#
{
  pkgs,
  lib,
  constants,
  mkMicrovm,
  mkTwoNodeVMs,
  mkTwoNodeServicesVMs ? null,
  microvmVariants,
  kwaainet,
  map-server,
  containers ? { },
  k8sManifests ? null,
}:
let
  lifecycleLib = import ./lib.nix { inherit pkgs lib; };
  kwaaiChecks = import ./kwaainet-checks.nix { inherit lib; };
  deepChecks = import ./deep-checks.nix { inherit lib; };
  resilienceChecks = import ./resilience-checks.nix { inherit lib; };
  p2pChecks = import ./p2p-checks.nix { inherit lib; };

  inherit (lifecycleLib)
    colorHelpers
    timingHelpers
    processHelpers
    consoleHelpers
    commonInputs
    sshInputs
    journalHelpers
    httpBodyHelpers
    peerHelpers
    tapHelpers
    ;

  sshHelpers = lifecycleLib.mkSshHelpers { sshPassword = constants.defaults.sshPassword; };

  # ─── Shared preamble (helpers + counters) and summary footer ──────────
  testPreamble = ''
    set +e

    ${colorHelpers}
    ${timingHelpers}
    ${processHelpers}
    ${consoleHelpers}
    ${sshHelpers}
    ${journalHelpers}
    ${httpBodyHelpers}
    ${peerHelpers}
    ${tapHelpers}

    TOTAL_START=$(time_ms)
    TOTAL_PASSED=0
    TOTAL_FAILED=0

    record_pass() { TOTAL_PASSED=$((TOTAL_PASSED + 1)); }
    record_fail() { TOTAL_FAILED=$((TOTAL_FAILED + 1)); }
  '';

  testSummary =
    { label, detail }:
    ''
      TOTAL_ELAPSED=$(elapsed_ms "$TOTAL_START")

      echo ""
      bold "========================================"
      if [[ $TOTAL_FAILED -eq 0 ]]; then
        success "  ${label} ($TOTAL_PASSED checks)"
        success "  ${detail}"
        success "  Total time: $(format_ms "$TOTAL_ELAPSED")"
      else
        error "  $TOTAL_FAILED PHASES FAILED ($TOTAL_PASSED passed)"
        error "  ${detail}"
      fi
      bold "========================================"

      [[ $TOTAL_FAILED -eq 0 ]]
    '';

  # ─── Full lifecycle test for a single-VM variant on a specific architecture ───
  mkFullTest =
    arch: variantName:
    let
      variantConfig = constants.variants.${variantName};
      portOffset = variantConfig.portOffset;
      archCfg = constants.architectures.${arch};
      archTimeouts = constants.getTimeouts arch;
      hostname = "kwaainet-${arch}-${variantName}-vm";
      consolePorts = constants.consolePorts arch portOffset;
      sshForwardPort = constants.sshForwardPort arch portOffset;
      vm = microvmVariants."${arch}-${variantName}";

      isDockerVariant = variantName == "docker";
      isK8sVariant = variantName == "k8s";
      isKwaainetVariant = builtins.elem "kwaainet" variantConfig.services;
      isFullStack = variantName == "full-stack";
      hasMapServer = builtins.elem "kwaainet-map-server" variantConfig.services;
      hasSummitServer = builtins.elem "kwaainet-summit-server" variantConfig.services;
      hasPostgres = builtins.elem "postgresql" variantConfig.services;
      isSingleNode = variantName == "single-node";
    in
    pkgs.writeShellApplication {
      name = "kwaainet-lifecycle-full-test-${arch}-${variantName}";
      runtimeInputs = commonInputs ++ sshInputs ++ [ pkgs.curl ];
      text = ''
        ${testPreamble}

        # Configuration
        VARIANT="${variantName}"
        ARCH="${arch}"
        HOSTNAME="${hostname}"
        SERIAL_PORT=${toString consolePorts.serial}
        VIRTIO_PORT=${toString consolePorts.virtio}
        SSH_HOST="localhost"
        SSH_PORT=${toString sshForwardPort}

        bold "========================================"
        bold "  KwaaiNet MicroVM Lifecycle Test"
        bold "  Variant: $VARIANT | Arch: $ARCH"
        bold "  ${archCfg.description}"
        bold "========================================"
        echo ""

        # ─── Phase 0: Build VM ─────────────────────────────────────────
        phase_header "0" "Build VM" "${toString archTimeouts.build}"
        info "  VM already built via Nix closure."
        result_pass "VM built" "0"
        record_pass

        # ─── Phase 1: Start VM ────────────────────────────────────────
        phase_header "1" "Start VM ($ARCH)" "${toString archTimeouts.start}"
        start_time=$(time_ms)

        if vm_is_running "$HOSTNAME"; then
          warn "  Killing existing VM..."
          kill_vm "$HOSTNAME"
          sleep 2
        fi

        info "  Starting VM..."
        ${vm.runner}/bin/microvm-run &
        VM_BG_PID=$!

        if wait_for_process "$HOSTNAME" "${toString archTimeouts.start}"; then
          elapsed=$(elapsed_ms "$start_time")
          pid=$(vm_pid "$HOSTNAME")
          result_pass "VM process running (PID: $pid)" "$elapsed"
          record_pass
        else
          elapsed=$(elapsed_ms "$start_time")
          result_fail "VM process not found" "$elapsed"
          record_fail
          exit 1
        fi

        # Ensure cleanup on exit
        cleanup() {
          kill_vm "$HOSTNAME" 2>/dev/null || true
          wait "$VM_BG_PID" 2>/dev/null || true
        }
        trap cleanup EXIT

        # ─── Phase 2: Serial Console ──────────────────────────────────
        phase_header "2" "Serial Console (${archCfg.consoleDevice})" "${toString archTimeouts.serial}"
        start_time=$(time_ms)
        if wait_for_console "$SERIAL_PORT" "${toString archTimeouts.serial}"; then
          result_pass "Serial console available (port $SERIAL_PORT)" "$(elapsed_ms "$start_time")"
          record_pass
        else
          result_fail "Serial console not available" "$(elapsed_ms "$start_time")"
          record_fail
        fi

        # ─── Phase 2b: Virtio Console ─────────────────────────────────
        phase_header "2b" "Virtio Console (hvc0)" "${toString archTimeouts.virtio}"
        start_time=$(time_ms)
        if wait_for_console "$VIRTIO_PORT" "${toString archTimeouts.virtio}"; then
          result_pass "Virtio console available (port $VIRTIO_PORT)" "$(elapsed_ms "$start_time")"
          record_pass
        else
          result_fail "Virtio console not available" "$(elapsed_ms "$start_time")"
          record_fail
        fi

        # ─── Phase 3: SSH + Service Verification ──────────────────────
        phase_header "3" "SSH reachable + Services" "${toString archTimeouts.services}"
        start_time=$(time_ms)

        info "  Waiting for SSH..."
        if ! wait_for_ssh "$SSH_HOST" "$SSH_PORT" "${toString archTimeouts.services}"; then
          result_fail "SSH not available" "$(elapsed_ms "$start_time")"
          record_fail
        else
          result_pass "SSH connected" "$(elapsed_ms "$start_time")"
          record_pass

          service_passed=0
          service_failed=0
          ${kwaaiChecks.mkServiceChecks { services = variantConfig.services; }}

          if [[ $service_failed -eq 0 ]]; then
            record_pass
          else
            record_fail
          fi
        fi

        ${lib.optionalString (!isDockerVariant && !isK8sVariant) ''
          # ─── Phase 3b: Security Audit ─────────────────────────────────
          phase_header "3b" "Security Audit" "${toString archTimeouts.security}"
          ${kwaaiChecks.mkSecurityChecks {
            services = builtins.filter (s: s != "postgresql") variantConfig.services;
          }}
        ''}

        ${lib.optionalString (isKwaainetVariant && !isDockerVariant && !isK8sVariant) ''
          # ─── Phase 3c: Startup Sequence ──────────────────────────────
          phase_header "3c" "Startup Sequence" "${toString archTimeouts.startupSequence}"
          ${deepChecks.mkStartupSequenceChecks}
        ''}

        ${lib.optionalString isFullStack ''
          # ─── Phase 3d: Service Dependency Order ──────────────────────
          phase_header "3d" "Service Dependency Order" "${toString archTimeouts.deepValidation}"
          ${deepChecks.mkDependencyOrderCheck {
            services = [
              "postgresql"
              "kwaainet"
              "kwaainet-map-server"
              "kwaainet-summit-server"
            ];
          }}
        ''}

        ${lib.optionalString (!isDockerVariant && !isK8sVariant) ''
          # ─── Phase 3e: Restart Stability ─────────────────────────────
          phase_header "3e" "Restart Stability" "${toString archTimeouts.deepValidation}"
          ${deepChecks.mkNoUnexpectedRestartsCheck {
            services = builtins.filter (s: s != "postgresql") variantConfig.services;
          }}
        ''}

        ${lib.optionalString isKwaainetVariant ''
          # ─── Phase 4: Node Verification ───────────────────────────────
          phase_header "4" "Node Verification" "${toString archTimeouts.node}"
          ${kwaaiChecks.mkNodeChecks}
        ''}

        ${lib.optionalString (isKwaainetVariant && !isDockerVariant && !isK8sVariant) ''
          # ─── Phase 4a: Deep Node Validation ──────────────────────────
          phase_header "4a" "Deep Node Validation" "${toString archTimeouts.deepValidation}"
          ${deepChecks.mkStatusDeepCheck}
          ${deepChecks.mkSocketCheck { }}
          ${deepChecks.mkIdentityPersistenceCheck}
        ''}

        ${lib.optionalString (variantConfig.httpChecks != [ ]) ''
          # ─── Phase 4b: HTTP Endpoint Checks ───────────────────────────
          phase_header "4b" "HTTP Endpoint Checks" "${toString archTimeouts.http}"
          ${kwaaiChecks.mkHttpChecks { httpChecks = variantConfig.httpChecks; }}
        ''}

        ${lib.optionalString (isKwaainetVariant && !isDockerVariant && !isK8sVariant) ''
          # ─── Phase 4c: Port Ownership ────────────────────────────────
          phase_header "4c" "Port Ownership" "${toString archTimeouts.deepValidation}"
          ${deepChecks.mkPortOwnerCheck {
            port = 8080;
            expectedProcess = "kwaainet";
          }}
        ''}

        ${lib.optionalString (hasMapServer && !isDockerVariant && !isK8sVariant) ''
          # ─── Phase 4d-map: Deep Map Server Checks ────────────────────
          phase_header "4d-map" "Deep Map Server Validation" "${toString archTimeouts.deepValidation}"
          ${deepChecks.mkMapServerHealthDeep { }}
          ${deepChecks.mkMapServerStatsCheck { }}
          ${deepChecks.mkMapServerNodesCheck { }}
        ''}

        ${lib.optionalString isDockerVariant ''
          # ─── Phase 4d: Docker Checks ─────────────────────────────────
          phase_header "4d" "Container Checks" "${toString archTimeouts.containers}"
          ${kwaaiChecks.mkDockerChecks { inherit containers; }}
        ''}

        ${lib.optionalString (isK8sVariant && k8sManifests != null) ''
          # ─── Phase 4e: K8s Checks ───────────────────────────────────
          phase_header "4e" "Kubernetes Checks" "${toString archTimeouts.k8s}"
          ${kwaaiChecks.mkK8sChecks { inherit k8sManifests; }}
        ''}

        ${lib.optionalString (hasPostgres && !isDockerVariant && !isK8sVariant) ''
          # ─── Phase 4f: Database Connectivity ─────────────────────────
          phase_header "4f" "Database Connectivity" "${toString archTimeouts.deepValidation}"
          ${deepChecks.mkPostgresConnectivityCheck}
        ''}

        ${lib.optionalString (isKwaainetVariant && !isDockerVariant && !isK8sVariant) ''
          # ─── Phase 5a: Restart Recovery ──────────────────────────────
          phase_header "5a" "Restart Recovery" "${toString archTimeouts.resilience}"
          ${resilienceChecks.mkRestartRecoveryCheck { service = "kwaainet"; }}
        ''}

        ${lib.optionalString (isSingleNode && isKwaainetVariant) ''
          # ─── Phase 5b: Identity Persistence ──────────────────────────
          phase_header "5b" "Identity Persistence" "${toString archTimeouts.resilience}"
          ${resilienceChecks.mkIdentityPersistenceAfterRestart { }}
        ''}

        ${lib.optionalString (isFullStack && hasPostgres) ''
          # ─── Phase 5c: Dependency Failure ────────────────────────────
          phase_header "5c" "Dependency Failure Recovery" "${toString archTimeouts.resilience}"
          ${resilienceChecks.mkDependencyFailureCheck {
            dependency = "postgresql";
            dependent = "kwaainet-summit-server";
          }}
        ''}

        # ─── Phase 5: Shutdown ─────────────────────────────────────────
        phase_header "5" "Shutdown" "${toString archTimeouts.shutdown}"
        start_time=$(time_ms)

        info "  Sending shutdown command..."
        # Use reboot — QEMU runs with -no-reboot so it exits on guest reboot.
        ssh_cmd "$SSH_HOST" "$SSH_PORT" "systemctl reboot" 2>/dev/null || true
        result_pass "Shutdown command sent" "$(elapsed_ms "$start_time")"
        record_pass

        # ─── Phase 6: Wait for Exit ───────────────────────────────────
        phase_header "6" "Clean Exit" "${toString archTimeouts.waitExit}"
        start_time=$(time_ms)

        # Give guest 30s to reboot cleanly.  If still running, send SIGTERM
        # to QEMU (clean ACPI shutdown) as a fallback — the SSH reboot command
        # may not have reached the guest if the connection was stale.
        if ! wait_for_exit "$HOSTNAME" 30; then
          info "  Guest still running after 30s, sending SIGTERM to QEMU..."
          qpid=$(vm_pid "$HOSTNAME")
          if [[ -n "$qpid" ]]; then
            kill "$qpid" 2>/dev/null || true
          fi
        fi

        # Wait for final exit (SIGTERM gives QEMU a few seconds to flush)
        if wait_for_exit "$HOSTNAME" 15; then
          result_pass "VM exited cleanly" "$(elapsed_ms "$start_time")"
          record_pass
        else
          result_fail "VM did not exit, forcing kill" "$(elapsed_ms "$start_time")"
          kill_vm "$HOSTNAME"
          record_fail
        fi

        # Remove trap since we're done
        trap - EXIT
        wait "$VM_BG_PID" 2>/dev/null || true

        # ─── Summary ──────────────────────────────────────────────────
        ${testSummary {
          label = "ALL PHASES PASSED";
          detail = "Arch: $ARCH | Variant: $VARIANT";
        }}
      '';
    };

  # ─── Two-node lifecycle test (generic, per-arch) ────────────────────────
  mkTwoNodeTestGeneric =
    {
      testName,
      testLabel,
      arch,
      mkVMs,
      portOffset ? 0,
      vmAServices ? [ "kwaainet" ],
      includeConsoleChecks ? true,
      includeStartupSequence ? true,
      includeDualSocketCheck ? true,
      extraChecks ? "",
    }:
    let
      archCfg = constants.architectures.${arch};
      archTimeouts = constants.getTimeouts arch;
      twoNodeVMs = mkVMs arch;
      vmA = twoNodeVMs.vmA;
      vmB = twoNodeVMs.vmB;
      vmAHost = constants.network.vmA;
      vmBHost = constants.network.vmB;
      serialPortsA = constants.consolePorts arch portOffset;
      hasExtraChecks = extraChecks != "";
      shutdownBPhase = if hasExtraChecks then "13" else "11";
      shutdownAPhase = if hasExtraChecks then "14" else "12";
    in
    pkgs.writeShellApplication {
      name = "kwaainet-lifecycle-full-test-${arch}-${testName}";
      runtimeInputs =
        commonInputs
        ++ sshInputs
        ++ [
          pkgs.curl
          pkgs.iproute2
        ];
      text = ''
        ${testPreamble}

        HOSTNAME_A="kwaainet-${arch}-${testName}-a-vm"
        HOSTNAME_B="kwaainet-${arch}-${testName}-b-vm"
        SSH_HOST_A="${vmAHost}"
        SSH_HOST_B="${vmBHost}"
        SSH_PORT=22
        PEER_ID_A=""
        PEER_ID_B=""

        cleanup() {
          kill_vm "$HOSTNAME_A" 2>/dev/null || true
          kill_vm "$HOSTNAME_B" 2>/dev/null || true
        }
        trap cleanup EXIT

        bold "========================================"
        bold "  KwaaiNet ${testLabel} Lifecycle Test"
        bold "  Arch: ${arch} | ${archCfg.description}"
        bold "========================================"
        echo ""

        # ─── Phase 0: TAP prerequisite ──────────────────────────────
        phase_header "0" "TAP Prerequisite" "5"
        if check_tap_available; then
          result_pass "Bridge ${constants.network.bridge} available" "0"
          record_pass
        else
          result_fail "Bridge ${constants.network.bridge} not found — run: sudo nix run .#kwaainet-network-setup" "0"
          record_fail
          exit 1
        fi

        # ─── Phase 1a: Start VM-A ──────────────────────────────────
        phase_header "1a" "Start VM-A (${arch})" "${toString archTimeouts.start}"
        start_time=$(time_ms)

        if vm_is_running "$HOSTNAME_A"; then
          warn "  Killing existing VM-A..."
          kill_vm "$HOSTNAME_A"
          sleep 2
        fi

        ${vmA.runner}/bin/microvm-run &
        VM_A_PID=$!

        if wait_for_process "$HOSTNAME_A" "${toString archTimeouts.start}"; then
          result_pass "VM-A running" "$(elapsed_ms "$start_time")"
          record_pass
        else
          result_fail "VM-A not started" "$(elapsed_ms "$start_time")"
          record_fail
          exit 1
        fi

        ${lib.optionalString includeConsoleChecks ''
          # ─── Phase 1b: VM-A Consoles ───────────────────────────────
          phase_header "1b" "VM-A Consoles" "${toString archTimeouts.serial}"
          start_time=$(time_ms)
          if wait_for_console "${toString serialPortsA.serial}" "${toString archTimeouts.serial}"; then
            result_pass "VM-A serial console" "$(elapsed_ms "$start_time")"
            record_pass
          else
            result_fail "VM-A serial console not available" "$(elapsed_ms "$start_time")"
            record_fail
          fi

          start_time=$(time_ms)
          if wait_for_console "${toString serialPortsA.virtio}" "${toString archTimeouts.virtio}"; then
            result_pass "VM-A virtio console" "$(elapsed_ms "$start_time")"
            record_pass
          else
            result_fail "VM-A virtio console not available" "$(elapsed_ms "$start_time")"
            record_fail
          fi
        ''}

        # ─── Phase 2: VM-A SSH + Services ──────────────────────────
        phase_header "2" "VM-A SSH + Services" "${toString archTimeouts.services}"
        start_time=$(time_ms)
        if wait_for_ssh "$SSH_HOST_A" "$SSH_PORT" "${toString archTimeouts.services}"; then
          result_pass "VM-A SSH connected" "$(elapsed_ms "$start_time")"
          record_pass
        else
          result_fail "VM-A SSH not available" "$(elapsed_ms "$start_time")"
          record_fail
        fi

        ${lib.concatMapStringsSep "\n" (svc: ''
          start_time=$(time_ms)
          if wait_for_service "$SSH_HOST_A" "$SSH_PORT" "${svc}" 60; then
            result_pass "VM-A ${svc} active" "$(elapsed_ms "$start_time")"
            record_pass
          else
            result_fail "VM-A ${svc} not active" "$(elapsed_ms "$start_time")"
            record_fail
          fi
        '') vmAServices}

        # ─── Phase 3: Extract VM-A Peer ID ─────────────────────────
        phase_header "3" "VM-A Peer ID" "${toString archTimeouts.node}"
        start_time=$(time_ms)
        PEER_ID_A=$(extract_peer_id "$SSH_HOST_A" "$SSH_PORT")
        if [[ -n "$PEER_ID_A" ]]; then
          result_pass "VM-A Peer ID: $PEER_ID_A" "$(elapsed_ms "$start_time")"
          record_pass
        else
          result_skip "VM-A Peer ID extraction failed (expected under TCG)"
        fi

        ${lib.optionalString includeStartupSequence ''
          # ─── Phase 3b: VM-A Startup Sequence ──────────────────────
          phase_header "3b" "VM-A Startup Sequence" "${toString archTimeouts.startupSequence}"
          for phase_num in 1 2 3 4 5; do
            seq_start=$(time_ms)
            if wait_for_journal_entry "$SSH_HOST_A" "$SSH_PORT" "kwaainet" "\[$phase_num/5\]" ${toString archTimeouts.startupSequence}; then
              result_pass "VM-A startup phase [$phase_num/5]" "$(elapsed_ms "$seq_start")"
              record_pass
            else
              result_skip "VM-A startup phase [$phase_num/5] not found"
            fi
          done
        ''}

        # ─── Phase 4a: Start VM-B ──────────────────────────────────
        phase_header "4a" "Start VM-B (${arch})" "${toString archTimeouts.start}"
        start_time=$(time_ms)

        if vm_is_running "$HOSTNAME_B"; then
          warn "  Killing existing VM-B..."
          kill_vm "$HOSTNAME_B"
          sleep 2
        fi

        ${vmB.runner}/bin/microvm-run &
        VM_B_PID=$!

        if wait_for_process "$HOSTNAME_B" "${toString archTimeouts.start}"; then
          result_pass "VM-B running" "$(elapsed_ms "$start_time")"
          record_pass
        else
          result_fail "VM-B not started" "$(elapsed_ms "$start_time")"
          record_fail
        fi

        # ─── Phase 4b: VM-B SSH + Service ──────────────────────────
        phase_header "4b" "VM-B SSH + Service" "${toString archTimeouts.services}"
        start_time=$(time_ms)
        if wait_for_ssh "$SSH_HOST_B" "$SSH_PORT" "${toString archTimeouts.services}"; then
          result_pass "VM-B SSH connected" "$(elapsed_ms "$start_time")"
          record_pass
        else
          result_fail "VM-B SSH not available" "$(elapsed_ms "$start_time")"
          record_fail
        fi

        start_time=$(time_ms)
        if wait_for_service "$SSH_HOST_B" "$SSH_PORT" "kwaainet" 60; then
          result_pass "VM-B kwaainet active" "$(elapsed_ms "$start_time")"
          record_pass
        else
          result_fail "VM-B kwaainet not active" "$(elapsed_ms "$start_time")"
          record_fail
        fi

        # ─── Phase 5: VM-B Peer ID + Distinct Check ───────────────
        phase_header "5" "VM-B Peer ID" "${toString archTimeouts.node}"
        start_time=$(time_ms)
        PEER_ID_B=$(extract_peer_id "$SSH_HOST_B" "$SSH_PORT")
        if [[ -n "$PEER_ID_B" ]]; then
          result_pass "VM-B Peer ID: $PEER_ID_B" "$(elapsed_ms "$start_time")"
          record_pass
        else
          result_skip "VM-B Peer ID extraction failed (expected under TCG)"
        fi

        ${p2pChecks.mkDistinctPeerIdsCheck}

        # ─── Phase 6: IPv6 Connectivity ────────────────────────────
        phase_header "6" "IPv6 Connectivity" "${toString archTimeouts.p2p}"
        ${p2pChecks.mkIPv6ConnectivityCheck {
          inherit vmAHost vmBHost;
        }}

        # ─── Phase 7: P2P Infrastructure ──────────────────────────
        phase_header "7" "P2P Infrastructure" "${toString archTimeouts.deepValidation}"
        ${lib.optionalString includeDualSocketCheck ''
          ${p2pChecks.mkDualSocketCheck {
            inherit vmAHost vmBHost;
          }}
        ''}
        ${p2pChecks.mkDualPortCheck {
          inherit vmAHost vmBHost;
        }}
        ${p2pChecks.mkCrossVmTcpCheck {
          inherit vmAHost vmBHost;
        }}

        # ─── Phase 8: Inject Bootstrap Peer ────────────────────────
        phase_header "8" "Bootstrap Peer Injection" "${toString archTimeouts.p2pBootstrap}"
        start_time=$(time_ms)
        if [[ -n "$PEER_ID_A" ]]; then
          MULTIADDR=$(build_multiaddr "${vmAHost}" "8080" "$PEER_ID_A")
          info "  Injecting: $MULTIADDR"
          inject_bootstrap_peer "$SSH_HOST_B" "$SSH_PORT" "$MULTIADDR"
          result_pass "Bootstrap peer injected into VM-B" "$(elapsed_ms "$start_time")"
          record_pass
        else
          result_skip "Bootstrap injection skipped (no VM-A Peer ID)"
        fi

        # ─── Phase 9: DHT Bootstrap ───────────────────────────────
        phase_header "9" "DHT Bootstrap" "${toString archTimeouts.p2pBootstrap}"
        start_time=$(time_ms)
        if [[ -n "$PEER_ID_A" ]]; then
          if wait_for_journal_entry "$SSH_HOST_B" "$SSH_PORT" "kwaainet" "ootstrap" ${toString archTimeouts.p2pBootstrap}; then
            result_pass "VM-B DHT bootstrap detected" "$(elapsed_ms "$start_time")"
            record_pass
          else
            result_skip "VM-B DHT bootstrap not detected within timeout"
          fi
        else
          result_skip "DHT bootstrap skipped (no Peer ID)"
        fi

        # ─── Phase 10: Peer Discovery ─────────────────────────────
        phase_header "10" "Peer Discovery" "${toString archTimeouts.p2pDiscovery}"
        ${p2pChecks.mkPeerDiscoveryCheck {
          observerHost = vmBHost;
        }}

        ${extraChecks}

        # ─── Phase ${shutdownBPhase}: Shutdown VM-B ──────────────────────────
        phase_header "${shutdownBPhase}" "Shutdown VM-B" "${toString archTimeouts.shutdown}"
        start_time=$(time_ms)
        ssh_cmd "$SSH_HOST_B" "$SSH_PORT" "systemctl reboot" 2>/dev/null || true
        if ! wait_for_exit "$HOSTNAME_B" 30; then
          qpid_b=$(vm_pid "$HOSTNAME_B")
          [[ -n "$qpid_b" ]] && kill "$qpid_b" 2>/dev/null || true
        fi
        if wait_for_exit "$HOSTNAME_B" 15; then
          result_pass "VM-B exited cleanly" "$(elapsed_ms "$start_time")"
          record_pass
        else
          kill_vm "$HOSTNAME_B"
          result_fail "VM-B forced kill" "$(elapsed_ms "$start_time")"
          record_fail
        fi

        # ─── Phase ${shutdownAPhase}: Shutdown VM-A ──────────────────────────
        phase_header "${shutdownAPhase}" "Shutdown VM-A" "${toString archTimeouts.shutdown}"
        start_time=$(time_ms)
        ssh_cmd "$SSH_HOST_A" "$SSH_PORT" "systemctl reboot" 2>/dev/null || true
        if ! wait_for_exit "$HOSTNAME_A" 30; then
          qpid_a=$(vm_pid "$HOSTNAME_A")
          [[ -n "$qpid_a" ]] && kill "$qpid_a" 2>/dev/null || true
        fi
        if wait_for_exit "$HOSTNAME_A" 15; then
          result_pass "VM-A exited cleanly" "$(elapsed_ms "$start_time")"
          record_pass
        else
          kill_vm "$HOSTNAME_A"
          result_fail "VM-A forced kill" "$(elapsed_ms "$start_time")"
          record_fail
        fi

        trap - EXIT
        wait "$VM_A_PID" 2>/dev/null || true
        wait "$VM_B_PID" 2>/dev/null || true

        ${testSummary {
          label = "${testLabel} TEST PASSED";
          detail = "Arch: ${arch}";
        }}
      '';
    };

  mkTwoNodeTest =
    arch:
    mkTwoNodeTestGeneric {
      testName = "two-node";
      testLabel = "TWO-NODE";
      inherit arch;
      mkVMs = mkTwoNodeVMs;
    };

  mkTwoNodeServicesTest =
    arch:
    let
      vmAHost = constants.network.vmA;
      archTimeouts = constants.getTimeouts arch;
    in
    mkTwoNodeTestGeneric {
      testName = "two-node-services";
      testLabel = "TWO-NODE-SERVICES";
      inherit arch;
      mkVMs = mkTwoNodeServicesVMs;
      portOffset = 100;
      vmAServices = [
        "kwaainet"
        "kwaainet-map-server"
      ];
      includeConsoleChecks = false;
      includeStartupSequence = false;
      includeDualSocketCheck = false;
      extraChecks = ''
        # ─── Phase 11: Map Server Discovery ────────────────────────
        phase_header "11" "Map Server Discovery" "${toString archTimeouts.p2pMapCrawl}"
        ${p2pChecks.mkMapServerNodeCountCheck {
          host = vmAHost;
        }}
        ${p2pChecks.mkMapServerPeerVisibleCheck {
          host = vmAHost;
        }}

        # ─── Phase 12: Map Server Deep Checks ─────────────────────
        phase_header "12" "Map Server Validation" "${toString archTimeouts.deepValidation}"
        # Temporarily set SSH_HOST for deep checks (they use $SSH_HOST)
        _saved_ssh_host="$SSH_HOST_A"
        SSH_HOST="$SSH_HOST_A"
        ${deepChecks.mkMapServerHealthDeep { }}
        ${deepChecks.mkMapServerStatsCheck { }}
        ${deepChecks.mkMapServerNodesCheck { }}
        SSH_HOST="$_saved_ssh_host"
      '';
    };

  # ─── All architectures and variants ───────────────────────────────────────
  # Derive available architectures from microvmVariants keys
  # (only archs with cross-compiled binaries will have variants)
  availableArchs = lib.unique (
    map (name: lib.head (lib.splitString "-" name)) (builtins.attrNames microvmVariants)
  );

  # User-mode variants (exclude two-node variants) per arch
  twoNodeVariants = [
    "two-node"
    "two-node-services"
  ];
  userVariantNames = builtins.filter (n: !builtins.elem n twoNodeVariants) (
    builtins.attrNames constants.variants
  );

  # Generate full tests: { "<arch>-<variant>" = test; }
  allFullTests = lib.concatMapAttrs (
    arch: _:
    let
      archAvailable = builtins.elem arch availableArchs;
    in
    lib.optionalAttrs archAvailable (
      (lib.listToAttrs (
        map (v: lib.nameValuePair "${arch}-${v}" (mkFullTest arch v)) (
          builtins.filter (
            v:
            builtins.elem v constants.archVariants.${arch}
            && !builtins.elem v twoNodeVariants
            && microvmVariants ? "${arch}-${v}"
          ) userVariantNames
        )
      ))
      // lib.optionalAttrs (builtins.elem "two-node" constants.archVariants.${arch}) {
        "${arch}-two-node" = mkTwoNodeTest arch;
      }
      //
        lib.optionalAttrs
          (builtins.elem "two-node-services" constants.archVariants.${arch} && mkTwoNodeServicesVMs != null)
          {
            "${arch}-two-node-services" = mkTwoNodeServicesTest arch;
          }
    )
  ) constants.architectures;

  # All variant names across all archs for test-all
  allTestNames = builtins.attrNames allFullTests;

  # ─── Test-all orchestrator ────────────────────────────────────────────────
  mkTestAll = pkgs.writeShellApplication {
    name = "kwaainet-lifecycle-test-all";
    runtimeInputs =
      commonInputs
      ++ sshInputs
      ++ [
        pkgs.curl
        pkgs.nix
        pkgs.iproute2
      ];
    text = ''
      set +e

      ${colorHelpers}
      ${timingHelpers}

      bold "========================================"
      bold "  KwaaiNet MicroVM Lifecycle Test Suite"
      bold "  Architectures: x86_64, aarch64, riscv64"
      bold "========================================"
      echo ""

      ALL_TESTS="${lib.concatStringsSep " " allTestNames}"
      SKIP_VARIANTS=""
      ONLY_VARIANT=""
      ONLY_ARCH=""

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --skip=*|--skip)
            if [[ "$1" == --skip=* ]]; then
              SKIP_VARIANTS="''${1#--skip=}"
            else
              shift; SKIP_VARIANTS="$1"
            fi
            shift ;;
          --only=*|--only)
            if [[ "$1" == --only=* ]]; then
              ONLY_VARIANT="''${1#--only=}"
            else
              shift; ONLY_VARIANT="$1"
            fi
            shift ;;
          --arch=*|--arch)
            if [[ "$1" == --arch=* ]]; then
              ONLY_ARCH="''${1#--arch=}"
            else
              shift; ONLY_ARCH="$1"
            fi
            shift ;;
          --help|-h)
            echo "Usage: kwaainet-lifecycle-test-all [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip=VARIANT   Skip specified variant (comma-separated)"
            echo "  --only=VARIANT   Test only specified variant"
            echo "  --arch=ARCH      Test only specified architecture (x86_64, aarch64, riscv64)"
            echo ""
            echo "Tests: ${lib.concatStringsSep " " allTestNames}"
            exit 0 ;;
          *)
            echo "Unknown option: $1"; exit 1 ;;
        esac
      done

      declare -A RESULTS
      declare -A DURATIONS
      TOTAL_PASSED=0
      TOTAL_FAILED=0
      TOTAL_SKIPPED=0
      SUITE_START=$(time_ms)

      for test_name in $ALL_TESTS; do
        # Filter by arch if specified
        if [[ -n "$ONLY_ARCH" ]] && [[ "$test_name" != "$ONLY_ARCH"* ]]; then
          RESULTS[$test_name]="SKIPPED"
          DURATIONS[$test_name]=0
          TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
          continue
        fi

        if [[ -n "$ONLY_VARIANT" ]] && [[ "$test_name" != *"$ONLY_VARIANT"* ]]; then
          RESULTS[$test_name]="SKIPPED"
          DURATIONS[$test_name]=0
          TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
          continue
        fi

        if [[ "$SKIP_VARIANTS" == *"$test_name"* ]]; then
          RESULTS[$test_name]="SKIPPED"
          DURATIONS[$test_name]=0
          TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
          continue
        fi

        # Skip two-node if TAP network not available
        if [[ "$test_name" == *"two-node"* ]]; then
          if ! ip link show ${constants.network.bridge} >/dev/null 2>&1; then
            RESULTS[$test_name]="SKIPPED (no TAP)"
            DURATIONS[$test_name]=0
            TOTAL_SKIPPED=$((TOTAL_SKIPPED + 1))
            continue
          fi
        fi

        echo ""
        bold "════════════════════════════════════════"
        bold "  Testing: $test_name"
        bold "════════════════════════════════════════"

        variant_start=$(time_ms)
        test_script="kwaainet-lifecycle-full-test-$test_name"

        if command -v "$test_script" >/dev/null 2>&1; then
          if "$test_script"; then
            RESULTS[$test_name]="PASSED"
            TOTAL_PASSED=$((TOTAL_PASSED + 1))
          else
            RESULTS[$test_name]="FAILED"
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
          fi
        else
          if nix run ".#$test_script" 2>/dev/null; then
            RESULTS[$test_name]="PASSED"
            TOTAL_PASSED=$((TOTAL_PASSED + 1))
          else
            RESULTS[$test_name]="FAILED"
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
          fi
        fi

        DURATIONS[$test_name]=$(elapsed_ms "$variant_start")
      done

      SUITE_ELAPSED=$(elapsed_ms "$SUITE_START")

      echo ""
      bold "========================================"
      bold "  Test Suite Summary"
      bold "========================================"
      echo ""

      printf "%-30s %-18s %12s\n" "Test" "Result" "Duration"
      printf "%-30s %-18s %12s\n" "────────────────────────" "────────────" "────────"

      for test_name in $ALL_TESTS; do
        result="''${RESULTS[$test_name]:-UNKNOWN}"
        duration="''${DURATIONS[$test_name]:-0}"

        if [[ "$result" == "PASSED" ]]; then
          printf "%-30s \033[32m%-18s\033[0m %12s\n" "$test_name" "$result" "$(format_ms "$duration")"
        elif [[ "$result" == "FAILED" ]]; then
          printf "%-30s \033[31m%-18s\033[0m %12s\n" "$test_name" "$result" "$(format_ms "$duration")"
        else
          printf "%-30s \033[33m%-18s\033[0m %12s\n" "$test_name" "$result" "-"
        fi
      done

      echo ""
      echo "────────────────────────────────────────"
      echo "Total: $TOTAL_PASSED passed, $TOTAL_FAILED failed, $TOTAL_SKIPPED skipped"
      echo "Total time: $(format_ms "$SUITE_ELAPSED")"
      echo "────────────────────────────────────────"

      [[ $TOTAL_FAILED -eq 0 ]]
    '';
  };

in
{
  # Full lifecycle tests per arch+variant
  tests = allFullTests // {
    all = mkTestAll;
  };

  # Flattened packages for flake integration
  packages =
    # Per-arch tests: kwaainet-lifecycle-full-test-<arch>-<variant>
    (lib.mapAttrs' (
      name: test: lib.nameValuePair "kwaainet-lifecycle-full-test-${name}" test
    ) allFullTests)
    # Backwards-compat aliases: kwaainet-lifecycle-full-test-<variant> → x86_64
    // (lib.mapAttrs' (
      n: v: lib.nameValuePair "kwaainet-lifecycle-full-test-${lib.removePrefix "x86_64-" n}" v
    ) (lib.filterAttrs (n: _: lib.hasPrefix "x86_64-" n) allFullTests))
    // {
      kwaainet-lifecycle-test-all = mkTestAll;
    };
}
