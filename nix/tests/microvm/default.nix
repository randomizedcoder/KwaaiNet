# Entry point for MicroVM lifecycle testing.
# Generates all microVM runner packages, lifecycle tests, and network scripts.
#
# Supports x86_64 (KVM), aarch64 (TCG), and riscv64 (TCG) architectures.
#
{
  pkgs,
  lib,
  nixpkgs,
  microvm,
  kwaainet,
  map-server,
  summit-server ? null,
  containers ? { },
  k8sManifests ? null,
  crossTargets ? { },
}:
let
  constants = import ./constants.nix;

  microvmLib = import ./microvm.nix {
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
  };

  lifecycle = import ./lifecycle {
    inherit
      pkgs
      lib
      constants
      kwaainet
      map-server
      containers
      k8sManifests
      ;
    inherit (microvmLib) mkMicrovm mkTwoNodeVMs mkTwoNodeServicesVMs;
    microvmVariants = microvmLib.variants;
  };

  networkSetup = import ./network-setup.nix { inherit pkgs; };

in
{
  packages =
    lifecycle.packages
    # VM runners: kwaainet-microvm-<arch>-<variant>
    // lib.mapAttrs' (
      name: vm: lib.nameValuePair "kwaainet-microvm-${name}" vm.runner
    ) microvmLib.variants
    # Backwards-compat aliases: kwaainet-microvm-<variant> → x86_64 variant
    // lib.mapAttrs' (
      n: v: lib.nameValuePair "kwaainet-microvm-${lib.removePrefix "x86_64-" n}" v.runner
    ) (lib.filterAttrs (n: _: lib.hasPrefix "x86_64-" n) microvmLib.variants)
    # Network scripts
    // {
      kwaainet-check-host = networkSetup.check;
      kwaainet-network-setup = networkSetup.setup;
      kwaainet-network-teardown = networkSetup.teardown;
    };
}
