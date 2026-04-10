# KwaaiNet — Sovereign AI Infrastructure
#
# Quick start:
#
#   # Enter the development shell (Rust, Go, protobuf, formatters)
#   nix develop
#
#   # Build the default binary (kwaainet)
#   nix build
#   ./result/bin/kwaainet --help
#
#   # Build a specific package
#   nix build .#kwaainet
#   nix build .#map-server
#   nix build .#p2pd
#
#   # Run checks (clippy + cargo test + smoke test)
#   nix flake check
#
#   # Run standalone integration tests (no VMs needed)
#   nix run .#test-two-node              # 2 kwaainet nodes
#   nix run .#test-two-node-services     # 2 nodes + map-server
#   nix run .#test-four-node             # 4 kwaainet nodes
#   nix run .#test-four-node-services    # 4 nodes + map-server
#
#   # Run all MicroVM lifecycle tests (Linux, requires KVM)
#   nix run .#kwaainet-lifecycle-test-all
#
#   # Format Nix files
#   nix fmt
#
# Inside the dev shell, run `kwaainet-help` for a full command reference.
# See nix/README.md for detailed documentation.
#
{
  description = "KwaaiNet — Sovereign AI Infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    crane.url = "github:ipetkov/crane";
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      crane,
      microvm,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;
        craneLib = crane.mkLib pkgs;
        packages = import ./nix/packages.nix { inherit pkgs; };
        p2pd = pkgs.callPackage ./nix/p2pd.nix { };
        protoRs = pkgs.callPackage ./nix/proto.nix { };
        cranePkgs = import ./nix/crane.nix {
          inherit
            craneLib
            p2pd
            protoRs
            packages
            ;
          inherit (pkgs) lib makeWrapper;
        };
        containers = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
          import ./nix/containers.nix {
            inherit pkgs;
            inherit (cranePkgs) kwaainet map-server;
          }
        );

        # --- Cross-compilation (x86_64-linux only) ---
        crossTargetDefs = {
          aarch64-linux-gnu = {
            crossConfig = "aarch64-unknown-linux-gnu";
            cargoTarget = "aarch64-unknown-linux-gnu";
          };
          aarch64-linux-musl = {
            crossConfig = "aarch64-unknown-linux-musl";
            cargoTarget = "aarch64-unknown-linux-musl";
          };
          x86_64-linux-musl = {
            crossConfig = "x86_64-unknown-linux-musl";
            cargoTarget = "x86_64-unknown-linux-musl";
          };
          riscv64-linux-gnu = {
            crossConfig = "riscv64-unknown-linux-gnu";
            cargoTarget = "riscv64gc-unknown-linux-gnu";
          };
        };

        crossTargets = lib.optionalAttrs (system == "x86_64-linux") (
          builtins.mapAttrs (
            name: def:
            import ./nix/cross.nix {
              inherit
                nixpkgs
                crane
                system
                protoRs
                ;
              targetName = name;
              crossSystem = {
                config = def.crossConfig;
              };
              cargoTarget = def.cargoTarget;
            }
          ) crossTargetDefs
        );

        # Flatten cross targets into suffixed package names.
        crossPackages = lib.concatMapAttrs (targetName: cross: {
          "kwaainet-${targetName}" = cross.kwaainet;
          "map-server-${targetName}" = cross.map-server;
          "p2pd-${targetName}" = cross.p2pd;
          "kwaainet-container-${targetName}" = cross.kwaainet-container;
          "map-server-container-${targetName}" = cross.map-server-container;
          "kwaainet-all-container-${targetName}" = cross.kwaainet-all-container;
        }) crossTargets;

        # Cross smoke tests — verify cross-compiled binaries run under QEMU.
        crossTests = lib.concatMapAttrs (
          targetName: cross:
          let
            parts = lib.splitString "-" targetName;
            arch = builtins.head parts;
            isMusl = lib.hasSuffix "musl" targetName;
          in
          {
            "test-cross-smoke-${targetName}" = import ./nix/tests/cross-smoke.nix {
              inherit pkgs arch;
              kwaainet = cross.kwaainet;
              isStatic = isMusl;
            };
          }
        ) crossTargets;

        # K8s manifests (Linux only)
        k8sManifests = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
          import ./nix/k8s-manifests { inherit pkgs lib; }
        );

        tests = import ./nix/tests {
          inherit
            pkgs
            containers
            crossTests
            nixpkgs
            k8sManifests
            microvm
            crossTargets
            ;
          kwaainet = cranePkgs.kwaainet;
          map-server = cranePkgs.map-server;
          summit-server = cranePkgs.summit-server or null; # null until summit-server added to workspace
        };
      in
      {
        packages = {
          default = cranePkgs.kwaainet;
          inherit (cranePkgs)
            kwaainet
            map-server
            cargoArtifacts
            ;
          inherit p2pd protoRs;
        }
        // lib.optionalAttrs (cranePkgs ? summit-server) {
          inherit (cranePkgs) summit-server;
        }
        // containers
        // crossPackages
        // tests.packages
        // (k8sManifests.packages or { });

        devShells.default = import ./nix/devshell.nix { inherit pkgs packages; };

        checks = {
          inherit (cranePkgs) clippy cargoTest;
        }
        // tests.checks;

        formatter = pkgs.nixfmt;
      }
    );
}
