# NixOS module for the KwaaiNet map-server.
#
# Usage:
#   services.kwaainet-map-server.enable = true;
#   services.kwaainet-map-server.package = map-server;
#
{
  config,
  lib,
  pkgs,
  map-server ? null,
  ...
}:
let
  cfg = config.services.kwaainet-map-server;
  hardening = import ./hardening.nix;
  modLib = import ./lib.nix { inherit lib; };
in
{
  options.services.kwaainet-map-server = {
    enable = lib.mkEnableOption "KwaaiNet map-server (network visualisation UI)";

    package = modLib.mkPackageOption {
      serviceName = "kwaainet-map-server";
      argName = "map-server";
      packageArg = map-server;
    };

    settings = {
      BIND_ADDR = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0:3030";
        description = "Address and port to bind.";
      };

      TOTAL_BLOCKS = lib.mkOption {
        type = lib.types.int;
        default = 80;
        description = "Total model blocks in the network.";
      };

      BOOTSTRAP_PEERS = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Bootstrap peer multiaddrs.";
      };

      ALLOWED_ORIGINS = lib.mkOption {
        type = lib.types.str;
        default = "*";
        description = "CORS allowed origins.";
      };

      socketPath = lib.mkOption {
        type = lib.types.str;
        default = "/run/kwaainet/p2pd.sock";
        description = "Path to the p2pd UNIX socket (shared with kwaainet).";
      };
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the map-server port in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.kwaainet-map-server = {
      description = "KwaaiNet Map Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        BIND_ADDR = cfg.settings.BIND_ADDR;
        TOTAL_BLOCKS = toString cfg.settings.TOTAL_BLOCKS;
        BOOTSTRAP_PEERS = lib.concatStringsSep " " cfg.settings.BOOTSTRAP_PEERS;
        ALLOWED_ORIGINS = cfg.settings.ALLOWED_ORIGINS;
        KWAAINET_SOCKET = cfg.settings.socketPath;
      };

      serviceConfig = hardening // {
        Type = "simple";
        DynamicUser = true;
        ExecStart = "${cfg.package}/bin/map-server";
        TimeoutStopSec = 10;

        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        # Override baseline IPAddressDeny — HTTP server needs networking
        IPAddressAllow = "any";
        IPAddressDeny = "";
        # Restrict bindable ports to only the configured HTTP port
        SocketBindAllow = [
          "tcp:${toString (modLib.portFromBindAddr cfg.settings.BIND_ADDR)}"
        ];
        SocketBindDeny = "any";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      (modLib.portFromBindAddr cfg.settings.BIND_ADDR)
    ];
  };
}
