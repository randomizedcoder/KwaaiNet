# TAP/bridge/vhost-net setup and teardown scripts for two-node testing.
# All network parameters come from constants.nix.
#
# Usage (setup and teardown require sudo):
#   nix run .#kwaainet-check-host            # Verify host environment
#   sudo nix run .#kwaainet-network-setup    # Create bridge + TAPs + NAT
#   sudo nix run .#kwaainet-network-teardown # Remove bridge + TAPs + NAT
#
{ pkgs }:
let
  constants = import ./constants.nix;
  inherit (constants.network)
    bridge
    gateway
    prefix
    tapA
    tapB
    tapC
    tapD
    ;
in
{
  # Host environment check
  check = pkgs.writeShellApplication {
    name = "kwaainet-check-host";
    runtimeInputs = with pkgs; [
      kmod
      coreutils
    ];
    text = ''
      echo "=== KwaaiNet MicroVM Host Environment Check ==="
      errors=0

      if [[ -c /dev/net/tun ]]; then
        echo "OK /dev/net/tun exists"
      else
        echo "FAIL /dev/net/tun not found"
        echo "  Run: sudo modprobe tun"
        errors=$((errors + 1))
      fi

      if lsmod | grep -q vhost_net; then
        echo "OK vhost_net module loaded"
      elif [[ -c /dev/vhost-net ]]; then
        echo "OK /dev/vhost-net exists"
      else
        echo "FAIL vhost_net not available"
        echo "  Run: sudo modprobe vhost_net"
        errors=$((errors + 1))
      fi

      if lsmod | grep -q bridge; then
        echo "OK bridge module loaded"
      else
        echo "INFO bridge module not loaded (will be loaded during setup)"
      fi

      if sudo -n true 2>/dev/null; then
        echo "OK sudo access available"
      else
        echo "FAIL sudo access required for network setup"
        errors=$((errors + 1))
      fi

      if [[ $errors -gt 0 ]]; then
        echo ""
        echo "Host environment check failed with $errors error(s)"
        exit 1
      else
        echo ""
        echo "Host environment ready for TAP networking"
      fi
    '';
  };

  # Network setup
  setup = pkgs.writeShellApplication {
    name = "kwaainet-network-setup";
    runtimeInputs = with pkgs; [
      iproute2
      kmod
      nftables
      acl
    ];
    text = ''
      echo "=== KwaaiNet MicroVM Network Setup ==="

      if [[ $EUID -ne 0 ]]; then
        echo "ERROR: Run with sudo: sudo nix run .#kwaainet-network-setup"
        exit 1
      fi

      REAL_USER="''${SUDO_USER:-$USER}"
      if [[ "$REAL_USER" == "root" ]]; then
        echo "ERROR: Run via 'sudo' as a regular user"
        exit 1
      fi
      echo "Setting up network for user: $REAL_USER"

      # Load kernel modules
      modprobe tun
      modprobe vhost_net
      modprobe bridge

      # Create bridge with IPv6
      if ! ip link show ${bridge} &>/dev/null; then
        echo "Creating bridge ${bridge}..."
        ip link add ${bridge} type bridge
        ip -6 addr add ${gateway}/64 dev ${bridge}
        ip link set ${bridge} up
      else
        echo "Bridge ${bridge} already exists"
      fi

      # Create TAP devices
      for tap in ${tapA} ${tapB} ${tapC} ${tapD}; do
        if ip link show "$tap" &>/dev/null; then
          echo "Removing existing TAP device $tap..."
          ip link del "$tap"
        fi
        echo "Creating TAP device $tap for user $REAL_USER..."
        ip tuntap add dev "$tap" mode tap user "$REAL_USER" multi_queue
        ip link set "$tap" master ${bridge}
        ip link set "$tap" up
      done

      # Enable vhost-net access
      if [[ -c /dev/vhost-net ]]; then
        if command -v setfacl &>/dev/null; then
          setfacl -m "u:$REAL_USER:rw" /dev/vhost-net
          echo "vhost-net enabled (ACL for $REAL_USER)"
        elif getent group kvm &>/dev/null; then
          chgrp kvm /dev/vhost-net
          chmod 660 /dev/vhost-net
          echo "vhost-net enabled (kvm group)"
        else
          echo "WARNING: Cannot set vhost-net permissions securely"
        fi
      fi

      # IPv6 forwarding
      sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null

      # Prevent br_netfilter from sending bridged L2 frames through
      # iptables/nftables — without this, inter-VM traffic on the bridge
      # gets dropped by host firewall rules.
      if [[ -d /proc/sys/net/bridge ]]; then
        sysctl -w net.bridge.bridge-nf-call-iptables=0 >/dev/null 2>&1 || true
        sysctl -w net.bridge.bridge-nf-call-ip6tables=0 >/dev/null 2>&1 || true
        echo "Disabled bridge-nf-call (L2 bypass for bridged traffic)"
      fi

      # NAT via nftables
      echo "Configuring NAT..."
      nft add table inet kwaainet-nat 2>/dev/null || true
      nft flush table inet kwaainet-nat 2>/dev/null || true
      nft -f - <<EOF
    table inet kwaainet-nat {
      chain postrouting {
        type nat hook postrouting priority 100;
        ip6 saddr ${prefix} masquerade
      }
      chain forward {
        type filter hook forward priority 0;
        iifname "${bridge}" accept
        oifname "${bridge}" ct state related,established accept
      }
    }
    EOF

      echo ""
      echo "Network ready. VMs will use:"
      echo "  VM-A: ${constants.network.vmA}"
      echo "  VM-B: ${constants.network.vmB}"
      echo "  VM-C: ${constants.network.vmC}"
      echo "  VM-D: ${constants.network.vmD}"
      echo "  Bridge: ${bridge}"
    '';
  };

  # Network teardown
  teardown = pkgs.writeShellApplication {
    name = "kwaainet-network-teardown";
    runtimeInputs = with pkgs; [
      iproute2
      nftables
    ];
    text = ''
      echo "=== KwaaiNet MicroVM Network Teardown ==="

      if [[ $EUID -ne 0 ]]; then
        echo "ERROR: Run with sudo: sudo nix run .#kwaainet-network-teardown"
        exit 1
      fi

      # Remove TAP devices
      for tap in ${tapA} ${tapB} ${tapC} ${tapD}; do
        if ip link show "$tap" &>/dev/null; then
          ip link del "$tap"
          echo "Removed TAP device $tap"
        fi
      done

      # Remove bridge
      if ip link show ${bridge} &>/dev/null; then
        ip link set ${bridge} down
        ip link del ${bridge}
        echo "Removed bridge ${bridge}"
      fi

      # Remove NAT rules
      nft delete table inet kwaainet-nat 2>/dev/null && \
        echo "Removed NAT rules" || true

      echo "Network teardown complete"
    '';
  };
}
