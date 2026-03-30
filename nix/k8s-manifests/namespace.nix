# Kubernetes Namespace manifest for KwaaiNet.
{ pkgs, constants }:
let
  yaml = ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: ${constants.k8s.namespace}
      labels:
        app: ${constants.k8s.labels.app}
  '';
in
{
  inherit yaml;
  file = pkgs.writeText "kwaainet-namespace.yaml" yaml;
}
