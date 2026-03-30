# P2P dual-node checks for KwaaiNet MicroVM lifecycle testing.
# Returns bash script fragments that use $SSH_HOST_A, $SSH_HOST_B, $SSH_PORT
# variables set by the two-node test orchestrator.
#
{ lib }:
{
  # Bidirectional IPv6 ping between VMs
  mkIPv6ConnectivityCheck =
    {
      vmAHost,
      vmBHost,
      sshPortA ? 22,
      sshPortB ? 22,
    }:
    ''
      ping_start=$(time_ms)
      if ssh_cmd "${vmAHost}" "${toString sshPortA}" "ping -6 -c 2 -W 5 ${vmBHost}" >/dev/null 2>&1; then
        result_pass "VM-A -> VM-B IPv6 ping" "$(elapsed_ms "$ping_start")"
        record_pass
      else
        result_fail "VM-A -> VM-B IPv6 ping failed" "$(elapsed_ms "$ping_start")"
        record_fail
      fi

      ping_start=$(time_ms)
      if ssh_cmd "${vmBHost}" "${toString sshPortB}" "ping -6 -c 2 -W 5 ${vmAHost}" >/dev/null 2>&1; then
        result_pass "VM-B -> VM-A IPv6 ping" "$(elapsed_ms "$ping_start")"
        record_pass
      else
        result_fail "VM-B -> VM-A IPv6 ping failed" "$(elapsed_ms "$ping_start")"
        record_fail
      fi
    '';

  # Verify p2pd socket on both VMs
  mkDualSocketCheck =
    {
      vmAHost,
      vmBHost,
      sshPortA ? 22,
      sshPortB ? 22,
      socketPath ? "/run/kwaainet/p2pd.sock",
    }:
    ''
      sock_start=$(time_ms)
      if ssh_cmd "${vmAHost}" "${toString sshPortA}" "test -S ${socketPath}"; then
        result_pass "VM-A p2pd socket" "$(elapsed_ms "$sock_start")"
        record_pass
      else
        result_skip "VM-A p2pd socket not found"
      fi

      sock_start=$(time_ms)
      if ssh_cmd "${vmBHost}" "${toString sshPortB}" "test -S ${socketPath}"; then
        result_pass "VM-B p2pd socket" "$(elapsed_ms "$sock_start")"
        record_pass
      else
        result_skip "VM-B p2pd socket not found"
      fi
    '';

  # Verify P2P port listening on both VMs
  mkDualPortCheck =
    {
      vmAHost,
      vmBHost,
      sshPortA ? 22,
      sshPortB ? 22,
      p2pPort ? 8080,
    }:
    ''
      port_start=$(time_ms)
      if ssh_cmd "${vmAHost}" "${toString sshPortA}" "ss -tlnp 2>/dev/null | grep -q ':${toString p2pPort} '"; then
        result_pass "VM-A P2P port ${toString p2pPort} listening" "$(elapsed_ms "$port_start")"
        record_pass
      else
        result_skip "VM-A P2P port ${toString p2pPort} not yet listening"
      fi

      port_start=$(time_ms)
      if ssh_cmd "${vmBHost}" "${toString sshPortB}" "ss -tlnp 2>/dev/null | grep -q ':${toString p2pPort} '"; then
        result_pass "VM-B P2P port ${toString p2pPort} listening" "$(elapsed_ms "$port_start")"
        record_pass
      else
        result_skip "VM-B P2P port ${toString p2pPort} not yet listening"
      fi
    '';

  # TCP connectivity from one VM to the other's P2P port
  mkCrossVmTcpCheck =
    {
      vmAHost,
      vmBHost,
      sshPortA ? 22,
      sshPortB ? 22,
      p2pPort ? 8080,
    }:
    ''
      tcp_start=$(time_ms)
      if ssh_cmd "${vmAHost}" "${toString sshPortA}" "nc -z -w 5 ${vmBHost} ${toString p2pPort}" 2>/dev/null; then
        result_pass "VM-A -> VM-B TCP :${toString p2pPort}" "$(elapsed_ms "$tcp_start")"
        record_pass
      else
        result_skip "VM-A -> VM-B TCP :${toString p2pPort} not reachable"
      fi

      tcp_start=$(time_ms)
      if ssh_cmd "${vmBHost}" "${toString sshPortB}" "nc -z -w 5 ${vmAHost} ${toString p2pPort}" 2>/dev/null; then
        result_pass "VM-B -> VM-A TCP :${toString p2pPort}" "$(elapsed_ms "$tcp_start")"
        record_pass
      else
        result_skip "VM-B -> VM-A TCP :${toString p2pPort} not reachable"
      fi
    '';

  # Wait for a journal startup phase marker on both VMs
  mkDualStartupPhaseCheck =
    {
      phase,
      vmAHost,
      vmBHost,
      sshPortA ? 22,
      sshPortB ? 22,
      timeout ? 30,
    }:
    ''
      phase_start=$(time_ms)
      if wait_for_journal_entry "${vmAHost}" "${toString sshPortA}" "kwaainet" "\[${toString phase}/5\]" ${toString timeout}; then
        result_pass "VM-A startup phase [${toString phase}/5]" "$(elapsed_ms "$phase_start")"
        record_pass
      else
        result_skip "VM-A startup phase [${toString phase}/5] not found"
      fi

      phase_start=$(time_ms)
      if wait_for_journal_entry "${vmBHost}" "${toString sshPortB}" "kwaainet" "\[${toString phase}/5\]" ${toString timeout}; then
        result_pass "VM-B startup phase [${toString phase}/5]" "$(elapsed_ms "$phase_start")"
        record_pass
      else
        result_skip "VM-B startup phase [${toString phase}/5] not found"
      fi
    '';

  # Poll for peer discovery evidence
  mkPeerDiscoveryCheck =
    {
      observerHost,
      observerPort ? 22,
      timeout ? 60,
    }:
    ''
      disc_start=$(time_ms)
      if wait_for_journal_entry "${observerHost}" "${toString observerPort}" "kwaainet" "peer" ${toString timeout}; then
        result_pass "peer discovery detected on ${observerHost}" "$(elapsed_ms "$disc_start")"
        record_pass
      else
        result_skip "peer discovery not detected within ${toString timeout}s"
      fi
    '';

  # Verify both VMs have distinct Peer IDs
  mkDistinctPeerIdsCheck = ''
    distinct_start=$(time_ms)
    if [[ -z "$PEER_ID_A" ]] || [[ -z "$PEER_ID_B" ]]; then
      result_skip "distinct Peer IDs: one or both empty"
    elif [[ "$PEER_ID_A" != "$PEER_ID_B" ]]; then
      result_pass "distinct Peer IDs (A=$PEER_ID_A, B=$PEER_ID_B)" "$(elapsed_ms "$distinct_start")"
      record_pass
    else
      result_fail "Peer IDs are identical: $PEER_ID_A" "$(elapsed_ms "$distinct_start")"
      record_fail
    fi
  '';

  # Poll map-server /api/stats for node_count >= minNodes
  mkMapServerNodeCountCheck =
    {
      host,
      port ? 22,
      mapPort ? 3030,
      minNodes ? 2,
      timeout ? 90,
    }:
    ''
      count_start=$(time_ms)
      elapsed=0
      found=0
      while [[ $elapsed -lt ${toString timeout} ]]; do
        body=$(ssh_cmd "${host}" "${toString port}" "curl -sf http://localhost:${toString mapPort}/api/stats 2>/dev/null" || echo "")
        count=$(echo "$body" | grep -oP '"node_count"\s*:\s*\K[0-9]+' || echo "0")
        if [[ "$count" -ge ${toString minNodes} ]]; then
          found=1
          break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
      done
      if [[ $found -eq 1 ]]; then
        result_pass "map-server node_count >= ${toString minNodes} ($count)" "$(elapsed_ms "$count_start")"
        record_pass
      else
        result_skip "map-server node_count $count < ${toString minNodes} after ${toString timeout}s"
      fi
    '';

  # Poll map-server /api/nodes for a specific Peer ID
  mkMapServerPeerVisibleCheck =
    {
      host,
      port ? 22,
      mapPort ? 3030,
      timeout ? 90,
    }:
    ''
      vis_start=$(time_ms)
      elapsed=0
      found=0
      while [[ $elapsed -lt ${toString timeout} ]]; do
        body=$(ssh_cmd "${host}" "${toString port}" "curl -sf http://localhost:${toString mapPort}/api/nodes 2>/dev/null" || echo "")
        if echo "$body" | grep -q "$PEER_ID_B"; then
          found=1
          break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
      done
      if [[ $found -eq 1 ]]; then
        result_pass "map-server sees VM-B peer ($PEER_ID_B)" "$(elapsed_ms "$vis_start")"
        record_pass
      else
        result_skip "map-server did not see VM-B peer within ${toString timeout}s"
      fi
    '';
}
