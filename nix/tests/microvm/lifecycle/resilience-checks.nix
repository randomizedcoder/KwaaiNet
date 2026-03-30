# Resilience checks for KwaaiNet MicroVM lifecycle testing.
# Returns bash script fragments for restart recovery, identity persistence,
# and dependency failure scenarios.
#
{ lib }:
{
  # Restart a service and verify it recovers
  mkRestartRecoveryCheck =
    { service, timeout ? 60 }:
    ''
      restart_start=$(time_ms)
      info "  Restarting ${service}..."
      ssh_cmd "$SSH_HOST" "$SSH_PORT" "systemctl restart ${service}" 2>/dev/null || true
      sleep 2
      if wait_for_service "$SSH_HOST" "$SSH_PORT" "${service}" ${toString timeout}; then
        result_pass "${service} recovered after restart" "$(elapsed_ms "$restart_start")"
        record_pass
      else
        result_fail "${service} did not recover after restart" "$(elapsed_ms "$restart_start")"
        record_fail
      fi
    '';

  # Verify Peer ID is stable across restart
  mkIdentityPersistenceAfterRestart =
    { timeout ? 60 }:
    ''
      id_persist_start=$(time_ms)
      PEER_ID_BEFORE=$(extract_peer_id "$SSH_HOST" "$SSH_PORT")
      if [[ -z "$PEER_ID_BEFORE" ]]; then
        result_skip "identity persistence: could not extract Peer ID before restart"
      else
        info "  Peer ID before restart: $PEER_ID_BEFORE"
        ssh_cmd "$SSH_HOST" "$SSH_PORT" "systemctl restart kwaainet" 2>/dev/null || true
        sleep 2
        if wait_for_service "$SSH_HOST" "$SSH_PORT" "kwaainet" ${toString timeout}; then
          PEER_ID_AFTER=$(extract_peer_id "$SSH_HOST" "$SSH_PORT")
          if [[ -z "$PEER_ID_AFTER" ]]; then
            result_skip "identity persistence: could not extract Peer ID after restart"
          elif [[ "$PEER_ID_BEFORE" == "$PEER_ID_AFTER" ]]; then
            result_pass "Peer ID stable across restart ($PEER_ID_BEFORE)" "$(elapsed_ms "$id_persist_start")"
            record_pass
          else
            result_fail "Peer ID changed: $PEER_ID_BEFORE -> $PEER_ID_AFTER" "$(elapsed_ms "$id_persist_start")"
            record_fail
          fi
        else
          result_fail "kwaainet did not recover for identity check" "$(elapsed_ms "$id_persist_start")"
          record_fail
        fi
      fi
    '';

  # Stop a dependency, verify dependent state, restart, verify recovery
  mkDependencyFailureCheck =
    {
      dependency,
      dependent,
      timeout ? 60,
    }:
    ''
      depfail_start=$(time_ms)
      info "  Stopping ${dependency}..."
      ssh_cmd "$SSH_HOST" "$SSH_PORT" "systemctl stop ${dependency}" 2>/dev/null || true
      sleep 3

      dep_status=$(ssh_cmd "$SSH_HOST" "$SSH_PORT" "systemctl is-active ${dependent}" 2>/dev/null || echo "unknown")
      info "  ${dependent} status after ${dependency} stop: $dep_status"

      info "  Restarting ${dependency}..."
      ssh_cmd "$SSH_HOST" "$SSH_PORT" "systemctl start ${dependency}" 2>/dev/null || true
      sleep 2

      # Restart the dependent if it's not active
      if ! check_service "$SSH_HOST" "$SSH_PORT" "${dependent}"; then
        ssh_cmd "$SSH_HOST" "$SSH_PORT" "systemctl restart ${dependent}" 2>/dev/null || true
      fi

      if wait_for_service "$SSH_HOST" "$SSH_PORT" "${dependent}" ${toString timeout}; then
        result_pass "${dependent} recovered after ${dependency} failure" "$(elapsed_ms "$depfail_start")"
        record_pass
      else
        result_fail "${dependent} did not recover after ${dependency} restart" "$(elapsed_ms "$depfail_start")"
        record_fail
      fi
    '';
}
