# Cross-compilation support — builds KwaaiNet binaries for foreign architectures.
#
# Called once per target from flake.nix.  Reuses crane.nix, p2pd.nix, and
# containers.nix unchanged — cross-compilation is handled by the cross pkgs.
#
# Cache optimization: build-host-only tools (remarshal, etc.) are pinned to
# the native package set via cross-cache.nix so they hit the binary cache
# instead of being rebuilt from source (~235 derivations / ~2.3 GiB saved).
{
  nixpkgs,
  crane,
  system,
  targetName, # e.g., "aarch64-linux-gnu"
  crossSystem, # e.g., { config = "aarch64-unknown-linux-gnu"; }
  cargoTarget, # e.g., "aarch64-unknown-linux-gnu"
  protoRs, # host-built protobuf (arch-independent)
}:

let
  # Native package set — tools from here match the binary cache hashes.
  pkgsNative = import nixpkgs { system = system; };

  pkgsCross = import nixpkgs {
    localSystem = system;
    inherit crossSystem;
    overlays = [
      (import ./overlays/cross-fixes.nix)
      (import ./overlays/cross-cache.nix { inherit pkgsNative; })
    ];
  };

  craneLib = crane.mkLib pkgsCross;

  packages = import ./packages.nix { pkgs = pkgsCross; };

  p2pd = pkgsCross.callPackage ./p2pd.nix { };

  cranePkgs = import ./crane.nix {
    inherit
      craneLib
      p2pd
      protoRs
      packages
      cargoTarget
      ;
    inherit (pkgsCross) lib makeWrapper;
  };

  containers = import ./containers.nix {
    pkgs = pkgsCross;
    inherit (cranePkgs) kwaainet map-server;
  };
in
{
  inherit (cranePkgs)
    kwaainet
    map-server
    cargoArtifacts
    ;
  inherit p2pd;
  inherit (containers) kwaainet-container map-server-container kwaainet-all-container;
}
