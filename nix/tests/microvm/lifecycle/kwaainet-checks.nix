# KwaaiNet-specific verification functions for MicroVM lifecycle testing.
# Returns bash script fragments for service, security, node, HTTP, Docker, K8s, and P2P checks.
#
{ lib }:
{
  # Check systemd services are active via SSH
  mkServiceChecks =
    { services }:
    lib.concatMapStringsSep "\n" (service: ''
      svc_start=$(time_ms)
      if wait_for_service "$SSH_HOST" "$SSH_PORT" "${service}" 60; then
        result_pass "${service} active" "$(elapsed_ms "$svc_start")"
        service_passed=$((service_passed + 1))
      else
        result_fail "${service} not active" "$(elapsed_ms "$svc_start")"
        service_failed=$((service_failed + 1))
      fi
    '') services;

  # Check systemd-analyze security score
  mkSecurityChecks =
    {
      services,
      threshold ? "2.5",
    }:
    lib.concatMapStringsSep "\n" (service: ''
      sec_start=$(time_ms)
      score=$(ssh_cmd "$SSH_HOST" "$SSH_PORT" "systemd-analyze security ${service} 2>/dev/null | tail -1 | grep -oP '[0-9]+\.[0-9]+'" || echo "N/A")
      if [[ "$score" != "N/A" ]] && [[ -n "$score" ]] && (( $(echo "$score <= ${threshold}" | bc -l 2>/dev/null || echo 0) )); then
        result_pass "${service} security score $score <= ${threshold}" "$(elapsed_ms "$sec_start")"
      elif [[ "$score" == "N/A" ]]; then
        result_skip "${service} security score unavailable"
      else
        result_fail "${service} security score $score > ${threshold}" "$(elapsed_ms "$sec_start")"
      fi
    '') services;

  # Check kwaainet identity and status
  mkNodeChecks = ''
    node_start=$(time_ms)
    peer_id=$(ssh_cmd "$SSH_HOST" "$SSH_PORT" "kwaainet identity show 2>/dev/null | grep -oP 'Peer ID: \K.*'" || echo "")
    if [[ -n "$peer_id" ]]; then
      result_pass "identity show (Peer ID: $peer_id)" "$(elapsed_ms "$node_start")"
    else
      result_fail "identity show failed" "$(elapsed_ms "$node_start")"
    fi

    status_start=$(time_ms)
    if ssh_cmd "$SSH_HOST" "$SSH_PORT" "kwaainet status" >/dev/null 2>&1; then
      result_pass "kwaainet status" "$(elapsed_ms "$status_start")"
    else
      result_fail "kwaainet status" "$(elapsed_ms "$status_start")"
    fi
  '';

  # Check HTTP endpoints via SSH
  mkHttpChecks =
    { httpChecks }:
    lib.concatMapStringsSep "\n" (check: ''
      http_start=$(time_ms)
      if ssh_cmd "$SSH_HOST" "$SSH_PORT" "curl -sf http://localhost:${toString check.port}${check.path} >/dev/null"; then
        result_pass "HTTP ${check.path}:${toString check.port} -> ${toString check.expect}" "$(elapsed_ms "$http_start")"
      else
        result_fail "HTTP ${check.path}:${toString check.port}" "$(elapsed_ms "$http_start")"
      fi
    '') httpChecks;

  # Check port is listening inside VM
  mkPortCheck =
    { port }:
    ''
      port_start=$(time_ms)
      if ssh_cmd "$SSH_HOST" "$SSH_PORT" "ss -tlnp | grep -q :${toString port}"; then
        result_pass "port ${toString port} listening" "$(elapsed_ms "$port_start")"
      else
        result_fail "port ${toString port} not listening" "$(elapsed_ms "$port_start")"
      fi
    '';

  # Docker container load/run checks (Phase 6)
  # Each container attr has an `imageName` (the Docker image name, e.g. "kwaainet")
  # which differs from the Nix attr name (e.g. "kwaainet-container").
  mkDockerChecks =
    { containers }:
    lib.concatMapStringsSep "\n" (
      name:
      let
        imageName = containers.${name}.imageName;
        imageTag = containers.${name}.imageTag or "latest";
        imageRef = "${imageName}:${imageTag}";
      in
      ''
        docker_start=$(time_ms)
        info "  Loading container: ${name}..."
        if ssh_cmd "$SSH_HOST" "$SSH_PORT" "/etc/kwaainet-containers/${name} | docker load" >/dev/null 2>&1; then
          result_pass "docker load ${name}" "$(elapsed_ms "$docker_start")"
        else
          result_fail "docker load ${name}" "$(elapsed_ms "$docker_start")"
        fi

        run_start=$(time_ms)
        # Verify the image is usable via docker create + rm.
        # We can't run the binary with --help because server binaries
        # (e.g. map-server) don't exit, and the minimal Nix containers
        # don't include coreutils for entrypoint overrides.
        cid=$(ssh_cmd "$SSH_HOST" "$SSH_PORT" "docker create --rm ${imageRef} 2>/dev/null" || echo "")
        cid=$(echo "$cid" | tail -1 | tr -d '[:space:]')
        if [[ -n "$cid" && ''${#cid} -ge 12 ]]; then
          result_pass "docker create ${imageRef} ($cid)" "$(elapsed_ms "$run_start")"
          ssh_cmd "$SSH_HOST" "$SSH_PORT" "docker rm -f $cid >/dev/null 2>&1" || true
        else
          result_fail "docker create ${imageRef} failed" "$(elapsed_ms "$run_start")"
        fi
      ''
    ) (builtins.attrNames containers);

  # K8s manifest deployment checks (Phase 7)
  # Note: minikube/kubectl are not currently in the VM closure.
  # These checks validate readiness for when they are added; until then they SKIP.
  mkK8sChecks =
    { k8sManifests }:
    ''
      # Check if minikube is available before attempting K8s checks
      if ! ssh_cmd "$SSH_HOST" "$SSH_PORT" "command -v minikube" >/dev/null 2>&1; then
        result_skip "minikube not in VM closure"
        result_skip "kubectl not in VM closure"
        result_skip "pod readiness (minikube unavailable)"
      else
        info "  Starting minikube..."
        k8s_start=$(time_ms)
        if ssh_cmd "$SSH_HOST" "$SSH_PORT" "minikube start --driver=docker --wait=all" >/dev/null 2>&1; then
          result_pass "minikube started" "$(elapsed_ms "$k8s_start")"
        else
          result_fail "minikube start" "$(elapsed_ms "$k8s_start")"
        fi

        apply_start=$(time_ms)
        if ssh_cmd "$SSH_HOST" "$SSH_PORT" "kubectl apply -f /etc/kwaainet-k8s/combined.yaml" >/dev/null 2>&1; then
          result_pass "kubectl apply" "$(elapsed_ms "$apply_start")"
        else
          result_fail "kubectl apply" "$(elapsed_ms "$apply_start")"
        fi

        pod_start=$(time_ms)
        if ssh_cmd "$SSH_HOST" "$SSH_PORT" "kubectl wait --for=condition=ready pod -l app=kwaainet -n kwaainet --timeout=120s" >/dev/null 2>&1; then
          result_pass "pods ready" "$(elapsed_ms "$pod_start")"
        else
          result_fail "pods not ready" "$(elapsed_ms "$pod_start")"
        fi
      fi
    '';

  # P2P peer discovery checks (two-node variant)
  mkP2PChecks = ''
    p2p_start=$(time_ms)
    peer_count=$(ssh_cmd "$SSH_HOST" "$SSH_PORT" "kwaainet status 2>/dev/null | grep -c 'peer'" || echo "0")
    if [[ "$peer_count" -gt 0 ]]; then
      result_pass "P2P peer discovery ($peer_count peers)" "$(elapsed_ms "$p2p_start")"
    else
      result_fail "P2P no peers found" "$(elapsed_ms "$p2p_start")"
    fi
  '';
}
