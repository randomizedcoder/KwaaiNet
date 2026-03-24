{
  description = "KwaaiNet — Sovereign AI Infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      crane,
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
        tests = import ./nix/tests {
          inherit pkgs containers;
          kwaainet = cranePkgs.kwaainet;
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
        // containers
        // tests.packages;

        devShells.default = import ./nix/devshell.nix { inherit pkgs packages; };

        checks = {
          inherit (cranePkgs) clippy cargoTest;
        }
        // tests.checks;

        formatter = pkgs.nixfmt;
      }
    );
}
