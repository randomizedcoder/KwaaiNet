# NixOS module for the KwaaiNet summit-server (WebAuthn + DID issuance).
#
# Usage:
#   services.kwaainet-summit-server.enable = true;
#   services.kwaainet-summit-server.package = summit-server;
#
# Requires PostgreSQL.
#
{
  config,
  lib,
  pkgs,
  summit-server ? null,
  ...
}:
let
  cfg = config.services.kwaainet-summit-server;
  hardening = import ./hardening.nix;
  modLib = import ./lib.nix { inherit lib; };
in
{
  options.services.kwaainet-summit-server = {
    enable = lib.mkEnableOption "KwaaiNet summit-server (WebAuthn + DID issuance)";

    package = modLib.mkPackageOption {
      serviceName = "kwaainet-summit-server";
      argName = "summit-server";
      packageArg = summit-server;
    };

    settings = {
      DATABASE_URL = lib.mkOption {
        type = lib.types.str;
        default = "postgresql:///summit?host=/run/postgresql";
        description = "PostgreSQL connection string.";
      };

      RP_ID = lib.mkOption {
        type = lib.types.str;
        default = "localhost";
        description = "WebAuthn Relying Party ID.";
      };

      RP_ORIGIN = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:3000";
        description = "WebAuthn Relying Party origin.";
      };

      SUMMIT_SIGNING_KEY_HEX = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Hex-encoded 32-byte signing key for DID issuance.";
      };

      BIND_ADDR = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0:3000";
        description = "Address and port to bind.";
      };
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the summit-server port in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.kwaainet-summit-server = {
      description = "KwaaiNet Summit Server";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "postgresql.service"
      ];
      requires = [ "postgresql.service" ];
      wants = [ "network-online.target" ];

      environment = {
        DATABASE_URL = cfg.settings.DATABASE_URL;
        RP_ID = cfg.settings.RP_ID;
        RP_ORIGIN = cfg.settings.RP_ORIGIN;
        SUMMIT_SIGNING_KEY_HEX = cfg.settings.SUMMIT_SIGNING_KEY_HEX;
        BIND_ADDR = cfg.settings.BIND_ADDR;
      };

      serviceConfig = hardening // {
        Type = "simple";
        # Static user must match the PostgreSQL role so peer auth works
        # over the Unix socket (DynamicUser would create a transient name
        # like "kwaainet-summit-server" that has no matching PG role).
        User = "summit";
        Group = "summit";
        ExecStart = "${cfg.package}/bin/summit-server";
        Restart = "on-failure";
        RestartSec = 3;
        TimeoutStopSec = 10;
        StateDirectory = "summit";

        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        # Override baseline IPAddressDeny — HTTP server + PostgreSQL need networking
        IPAddressAllow = "any";
        IPAddressDeny = "";
        # Restrict bindable ports to only the configured HTTP port
        SocketBindAllow = [
          "tcp:${toString (modLib.portFromBindAddr cfg.settings.BIND_ADDR)}"
        ];
        SocketBindDeny = "any";
      };
    };

    # Static system user matching the PostgreSQL role name
    users.users.summit = {
      isSystemUser = true;
      group = "summit";
      home = "/var/lib/summit";
    };
    users.groups.summit = { };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      (modLib.portFromBindAddr cfg.settings.BIND_ADDR)
    ];
  };
}
