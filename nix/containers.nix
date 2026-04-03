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
  # Returns the derivation with an extra `inputsHash` attribute so tests
  # can skip `docker load` when the image hasn't changed.
  mkContainer =
    {
      name,
      binary,
      port ? null,
      extraContents ? [ ],
      extraConfig ? { },
      entrypoint ? [ "${binary}/bin/${name}" ],
    }:
    let
      allContents = [ binary ] ++ baseContents ++ extraContents;
      inputsHash = builtins.substring 0 32 (
        builtins.hashString "sha256" (
          builtins.concatStringsSep ":" (map (p: p.outPath) allContents)
        )
      );
      image = pkgs.dockerTools.streamLayeredImage ({
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
            "nix.inputs.hash" = inputsHash;
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
      imageTag = binary.version or "latest";
    in
    image // { inherit inputsHash imageTag; };

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
