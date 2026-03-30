# Kubernetes Service manifest for KwaaiNet map-server.
{ pkgs, constants }:
let
  k = constants.k8s;
  yaml = ''
    apiVersion: v1
    kind: Service
    metadata:
      name: ${k.deploymentName}-map
      namespace: ${k.namespace}
      labels:
        app: ${k.labels.app}
    spec:
      type: ClusterIP
      selector:
        app: ${k.labels.app}
      ports:
        - port: ${toString k.ports.mapServer}
          targetPort: ${toString k.ports.mapServer}
          protocol: TCP
          name: http
  '';
in
{
  inherit yaml;
  file = pkgs.writeText "kwaainet-service.yaml" yaml;
}
