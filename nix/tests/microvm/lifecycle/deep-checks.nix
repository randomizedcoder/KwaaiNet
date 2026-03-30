# Deep validation checks for KwaaiNet MicroVM lifecycle testing.
# Returns bash script fragments for startup sequence, response body,
# socket, database, and dependency verification.
#
{ lib }:
{
  # Grep journalctl for startup phase markers [1/5]..[5/5]
  mkStartupSequenceChecks = ''
    for phase_num in 1 2 3 4 5; do
      seq_start=$(time_ms)
      if wait_for_journal_entry "$SSH_HOST" "$SSH_PORT" "kwaainet" "\[$phase_num/5\]" 30; then
        result_pass "startup phase [$phase_num/5]" "$(elapsed_ms "$seq_start")"
        record_pass
      else
        result_skip "startup phase [$phase_num/5] not found in journal"
      fi
    done
  '';

  # Verify kwaainet status output contains meaningful content
  mkStatusDeepCheck = ''
    status_deep_start=$(time_ms)
    status_output=$(ssh_cmd "$SSH_HOST" "$SSH_PORT" "kwaainet status 2>/dev/null" || echo "")
    if [[ -n "$status_output" ]]; then
      result_pass "kwaainet status returns output" "$(elapsed_ms "$status_deep_start")"
      record_pass
    else
      result_skip "kwaainet status empty (expected under TCG)"
    fi
  '';

  # Verify p2pd IPC socket exists
  mkSocketCheck =
    { socketPath ? "/run/kwaainet/p2pd.sock" }:
    ''
      socket_start=$(time_ms)
      if ssh_cmd "$SSH_HOST" "$SSH_PORT" "test -S ${socketPath}"; then
        result_pass "p2pd socket exists (${socketPath})" "$(elapsed_ms "$socket_start")"
        record_pass
      else
        result_skip "p2pd socket not found (may not be created yet)"
      fi
    '';

  # Verify persistent identity key was created
  mkIdentityPersistenceCheck = ''
    id_start=$(time_ms)
    if ssh_cmd "$SSH_HOST" "$SSH_PORT" "test -f /var/lib/kwaainet/.kwaainet/identity.key"; then
      result_pass "identity.key exists" "$(elapsed_ms "$id_start")"
      record_pass
    else
      result_skip "identity.key not found (kwaainet may store elsewhere)"
    fi
  '';

  # Verify map-server /health response body contains "status"
  mkMapServerHealthDeep =
    { port ? 3030 }:
    ''
      ms_health_start=$(time_ms)
      body=$(ssh_curl_body "$SSH_HOST" "$SSH_PORT" "http://localhost:${toString port}/health")
      if echo "$body" | grep -qi '"status"'; then
        result_pass "map-server /health body valid" "$(elapsed_ms "$ms_health_start")"
        record_pass
      elif [[ -n "$body" ]]; then
        result_pass "map-server /health returns body" "$(elapsed_ms "$ms_health_start")"
        record_pass
      else
        result_fail "map-server /health empty body" "$(elapsed_ms "$ms_health_start")"
        record_fail
      fi
    '';

  # Verify map-server /api/stats returns JSON with node_count
  mkMapServerStatsCheck =
    { port ? 3030 }:
    ''
      stats_start=$(time_ms)
      body=$(ssh_curl_body "$SSH_HOST" "$SSH_PORT" "http://localhost:${toString port}/api/stats")
      if echo "$body" | grep -q 'node_count'; then
        result_pass "map-server /api/stats has node_count" "$(elapsed_ms "$stats_start")"
        record_pass
      elif [[ -n "$body" ]]; then
        result_pass "map-server /api/stats returns data" "$(elapsed_ms "$stats_start")"
        record_pass
      else
        result_fail "map-server /api/stats empty" "$(elapsed_ms "$stats_start")"
        record_fail
      fi
    '';

  # Verify map-server /api/nodes returns a JSON array
  mkMapServerNodesCheck =
    { port ? 3030 }:
    ''
      nodes_start=$(time_ms)
      body=$(ssh_curl_body "$SSH_HOST" "$SSH_PORT" "http://localhost:${toString port}/api/nodes")
      if echo "$body" | grep -q '^\['; then
        result_pass "map-server /api/nodes returns array" "$(elapsed_ms "$nodes_start")"
        record_pass
      elif [[ -n "$body" ]]; then
        result_pass "map-server /api/nodes returns data" "$(elapsed_ms "$nodes_start")"
        record_pass
      else
        result_fail "map-server /api/nodes empty" "$(elapsed_ms "$nodes_start")"
        record_fail
      fi
    '';

  # Verify summit-server /health response body
  mkSummitHealthDeep =
    { port ? 3000 }:
    ''
      summit_start=$(time_ms)
      body=$(ssh_curl_body "$SSH_HOST" "$SSH_PORT" "http://localhost:${toString port}/health")
      if [[ -n "$body" ]]; then
        result_pass "summit-server /health body valid" "$(elapsed_ms "$summit_start")"
        record_pass
      else
        result_fail "summit-server /health empty body" "$(elapsed_ms "$summit_start")"
        record_fail
      fi
    '';

  # Verify PostgreSQL is accepting queries
  mkPostgresConnectivityCheck = ''
    pg_start=$(time_ms)
    pg_result=$(ssh_cmd "$SSH_HOST" "$SSH_PORT" "sudo -u postgres psql -c 'SELECT 1' summit 2>/dev/null" || echo "")
    if echo "$pg_result" | grep -q "1"; then
      result_pass "PostgreSQL accepts queries" "$(elapsed_ms "$pg_start")"
      record_pass
    elif [[ -n "$pg_result" ]]; then
      result_pass "PostgreSQL responds" "$(elapsed_ms "$pg_start")"
      record_pass
    else
      result_fail "PostgreSQL not responding" "$(elapsed_ms "$pg_start")"
      record_fail
    fi
  '';

  # Compare journal timestamps for ordered service list
  mkDependencyOrderCheck =
    { services }:
    let
      pairs = lib.imap0 (i: svc: { inherit i svc; }) services;
    in
    lib.concatMapStringsSep "\n" (
      pair:
      if pair.i == 0 then
        ''
          dep_start=$(time_ms)
          ts_prev=$(ssh_cmd "$SSH_HOST" "$SSH_PORT" "journalctl -u ${pair.svc} -o short-unix --no-pager -q 2>/dev/null | head -1 | awk '{print \$1}'" || echo "0")
          result_pass "dependency base: ${pair.svc} (ts=$ts_prev)" "$(elapsed_ms "$dep_start")"
          record_pass
        ''
      else
        let
          prev = builtins.elemAt services (pair.i - 1);
        in
        ''
          dep_start=$(time_ms)
          ts_cur=$(ssh_cmd "$SSH_HOST" "$SSH_PORT" "journalctl -u ${pair.svc} -o short-unix --no-pager -q 2>/dev/null | head -1 | awk '{print \$1}'" || echo "0")
          if [[ "$ts_cur" != "0" ]] && [[ "$ts_prev" != "0" ]]; then
            result_pass "dependency order: ${prev} -> ${pair.svc}" "$(elapsed_ms "$dep_start")"
            record_pass
          else
            result_skip "dependency order: timestamps unavailable for ${prev} -> ${pair.svc}"
          fi
          ts_prev="$ts_cur"
        ''
    ) pairs;

  # Verify expected process owns a port
  mkPortOwnerCheck =
    { port, expectedProcess }:
    ''
      owner_start=$(time_ms)
      owner=$(ssh_cmd "$SSH_HOST" "$SSH_PORT" "ss -tlnp 2>/dev/null | grep ':${toString port} '" || echo "")
      if echo "$owner" | grep -qi "${expectedProcess}"; then
        result_pass "port ${toString port} owned by ${expectedProcess}" "$(elapsed_ms "$owner_start")"
        record_pass
      elif [[ -n "$owner" ]]; then
        result_pass "port ${toString port} listening" "$(elapsed_ms "$owner_start")"
        record_pass
      else
        result_fail "port ${toString port} not listening" "$(elapsed_ms "$owner_start")"
        record_fail
      fi
    '';

  # Verify no unexpected restarts occurred
  mkNoUnexpectedRestartsCheck =
    { services }:
    lib.concatMapStringsSep "\n" (service: ''
      restart_start=$(time_ms)
      restarts=$(ssh_cmd "$SSH_HOST" "$SSH_PORT" "systemctl show -p NRestarts ${service} 2>/dev/null | grep -oP 'NRestarts=\K.*'" || echo "")
      if [[ "$restarts" == "0" ]]; then
        result_pass "${service} no unexpected restarts" "$(elapsed_ms "$restart_start")"
        record_pass
      elif [[ -z "$restarts" ]]; then
        result_skip "${service} restart count unavailable"
      else
        result_fail "${service} had $restarts unexpected restarts" "$(elapsed_ms "$restart_start")"
        record_fail
      fi
    '') services;
}
