# OCI container images for KwaaiNet binaries.
#
# Each image uses streamLayeredImage — the derivation output is an
# executable script that streams a Docker-compatible tarball to stdout.
#
# Usage:
#   nix build .#kwaainet-container && ./result | docker load
#   nix build .#kwaainet-container && ./result | podman load
#
# Inputs:
#   pkgs             — nixpkgs package set
#   kwaainet         — kwaainet binary derivation (includes bundled p2pd)
#   map-server       — map-server binary derivation
{
  pkgs,
  kwaainet,
  map-server,
}:

let
  # Shared base contents for all containers.
  baseContents = [
    pkgs.cacert # TLS CA certificates
    pkgs.tzdata # timezone data for log timestamps
  ];

  # Helper — builds a streamLayeredImage for a single binary.
  mkContainer =
    {
      name,
      binary,
      port ? null,
      extraContents ? [ ],
      extraConfig ? { },
      entrypoint ? [ "${binary}/bin/${name}" ],
    }:
    pkgs.dockerTools.streamLayeredImage ({
      inherit name;
      tag = binary.version or "latest";

      contents = baseContents ++ [ binary ] ++ extraContents;

      config = {
        Entrypoint = entrypoint;
        Env = [
          "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          "TZDIR=${pkgs.tzdata}/share/zoneinfo"
        ];
        Labels = {
          "nix.inputs.hash" = builtins.hashString "sha256" (
            builtins.toJSON (map toString ([ binary ] ++ baseContents ++ extraContents))
          );
        };
      }
      // (
        if port != null then
          {
            ExposedPorts = {
              "${toString port}/tcp" = { };
            };
          }
        else
          { }
      )
      // extraConfig;
    });

in
{
  kwaainet-container = mkContainer {
    name = "kwaainet";
    binary = kwaainet;
  };

  map-server-container = mkContainer {
    name = "map-server";
    binary = map-server;
    port = 3030;
  };

  # All-in-one container with every KwaaiNet binary.
  kwaainet-all-container = mkContainer {
    name = "kwaainet-all";
    binary = kwaainet;
    port = 3030;
    entrypoint = [ "${kwaainet}/bin/kwaainet" ];
    extraContents = [ map-server ];
  };
}
