# Shared helpers for KwaaiNet NixOS service modules.
{ lib }:
{
  # Extract port number from "host:port" or ":port" bind address string.
  portFromBindAddr =
    bindAddr:
    let
      parts = lib.splitString ":" bindAddr;
    in
    lib.toInt (lib.last parts);

  # Common package option — default pulls from specialArgs, throws if absent.
  mkPackageOption =
    {
      serviceName,
      argName,
      packageArg ? null,
    }:
    lib.mkOption {
      type = lib.types.package;
      default =
        if packageArg != null then
          packageArg
        else
          throw "${serviceName} package not found. Pass via specialArgs or set services.${serviceName}.package.";
      defaultText = lib.literalExpression "${argName} (from specialArgs)";
      description = "The ${argName} package to use.";
    };
}
