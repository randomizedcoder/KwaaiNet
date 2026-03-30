# NixOS module for the KwaaiNet P2P node.
#
# Usage:
#   services.kwaainet.enable = true;
#   services.kwaainet.package = kwaainet;  # or passed via specialArgs
#
# kwaainet spawns p2pd internally — no separate p2pd service needed.
# HOME is set to /var/lib/kwaainet so config lives at /var/lib/kwaainet/.kwaainet/
#
{
  config,
  lib,
  pkgs,
  kwaainet ? null,
  ...
}:
let
  cfg = config.services.kwaainet;
  hardening = import ./hardening.nix;
  modLib = import ./lib.nix { inherit lib; };
in
{
  options.services.kwaainet = {
    enable = lib.mkEnableOption "KwaaiNet P2P inference node";

    package = modLib.mkPackageOption {
      serviceName = "kwaainet";
      argName = "kwaainet";
      packageArg = kwaainet;
    };

    settings = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "P2P listen port.";
      };

      blocks = lib.mkOption {
        type = lib.types.int;
        default = 8;
        description = "Number of model blocks to serve.";
      };

      start_block = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Starting block index (0 = auto).";
      };

      public_name = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Public name for this node.";
      };

      use_gpu = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to use GPU acceleration. Disabled by default for VMs.";
      };

      initial_peers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Bootstrap peer multiaddrs.";
      };

      no_relay = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Disable relay connectivity.";
      };

      announce_addr = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Public multiaddr to announce.";
      };
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the P2P port in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Put kwaainet CLI on PATH for operators (identity show, status, etc.)
    environment.systemPackages = [ cfg.package ];

    users.users.kwaainet = {
      isSystemUser = true;
      group = "kwaainet";
      description = "KwaaiNet service user";
    };
    users.groups.kwaainet = { };

    systemd.services.kwaainet = {
      description = "KwaaiNet P2P Inference Node";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        HOME = "/var/lib/kwaainet";
        KWAAINET_SOCKET = "/run/kwaainet/p2pd.sock";
      };

      serviceConfig = hardening // {
        Type = "simple";
        User = "kwaainet";
        Group = "kwaainet";
        StateDirectory = "kwaainet";
        RuntimeDirectory = "kwaainet";
        TimeoutStopSec = 10;

        ExecStartPre = "${cfg.package}/bin/kwaainet setup";
        ExecStart =
          let
            port = toString cfg.settings.port;
            blocks = toString cfg.settings.blocks;
            startBlock = toString cfg.settings.start_block;
            peers = lib.concatStringsSep "," cfg.settings.initial_peers;
          in
          lib.concatStringsSep " " (
            [
              "${cfg.package}/bin/kwaainet"
              "start"
              "--port"
              port
              "--blocks"
              blocks
            ]
            ++ lib.optionals (!cfg.settings.use_gpu) [ "--no-gpu" ]
            ++ lib.optionals (cfg.settings.start_block > 0) [
              "--start-block"
              startBlock
            ]
            ++ lib.optionals (cfg.settings.public_name != "") [
              "--public-name"
              cfg.settings.public_name
            ]
            ++ lib.optionals cfg.settings.no_relay [ "--no-relay" ]
            ++ lib.optionals (cfg.settings.announce_addr != "") [
              "--announce-addr"
              cfg.settings.announce_addr
            ]
            ++ lib.optionals (cfg.settings.initial_peers != [ ]) [
              "--initial-peers"
              peers
            ]
          );

        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        ReadWritePaths = [
          "/var/lib/kwaainet"
          "/run/kwaainet"
        ];
        # Override baseline IPAddressDeny — P2P needs unrestricted networking
        IPAddressAllow = "any";
        IPAddressDeny = "";
        # P2P listen + UDP, plus unrestricted TCP for ephemeral RPC handler
        # (node.rs binds 127.0.0.1:0 — BPF sees port 0, not the assigned port)
        SocketBindAllow = [
          "tcp"
          "udp:${toString cfg.settings.port}"
        ];
        SocketBindDeny = "any";

        Slice = "kwaainet.slice";
      };
    };

    systemd.slices.kwaainet = {
      description = "KwaaiNet Resource Slice";
      sliceConfig = {
        MemoryHigh = "80%";
        MemoryMax = "90%";
        CPUQuota = "80%";
        TasksMax = 512;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.settings.port ];
  };
}
