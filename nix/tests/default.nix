# Test orchestration — exposes checks (sandboxed) and runnable test scripts.
{
  pkgs,
  kwaainet,
  map-server ? null,
  summit-server ? null,
  nixpkgs ? null,
  containers ? { },
  crossTests ? { },
  k8sManifests ? null,
  microvm ? null,
  crossTargets ? { },
}:

let
  lib = pkgs.lib;
  smoke = import ./smoke.nix { inherit pkgs kwaainet; };
  twoNode = import ./two-node.nix { inherit pkgs kwaainet; };
  containerTest = import ./containers.nix { inherit pkgs containers; };
  fullRebuild = import ./full-rebuild.nix { inherit pkgs; };

  # MicroVM lifecycle tests (Linux only, requires nixpkgs + microvm for nixosSystem)
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  microvmTests = lib.optionalAttrs (nixpkgs != null && microvm != null && isLinux) (
    import ./microvm {
      inherit
        pkgs
        lib
        nixpkgs
        microvm
        kwaainet
        map-server
        summit-server
        containers
        k8sManifests
        crossTargets
        ;
    }
  );
in
{
  # Sandboxed checks — run via `nix flake check`
  checks = {
    kwaainet-smoke = smoke;
  };

  # Runnable test scripts — run via `nix run .#test-<name>`
  packages = {
    test-two-node = twoNode;
    full-rebuild = fullRebuild;
  }
  // lib.optionalAttrs (containers != { }) {
    test-containers = containerTest;
  }
  // crossTests
  // (microvmTests.packages or { });
}
