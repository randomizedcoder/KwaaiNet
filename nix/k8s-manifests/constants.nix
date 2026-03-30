# K8s manifest constants for KwaaiNet deployment.
{ }:
{
  k8s = {
    namespace = "kwaainet";
    deploymentName = "kwaainet";
    labels = {
      app = "kwaainet";
      component = "inference-node";
    };
    image = {
      name = "kwaainet";
      tag = "latest";
      pullPolicy = "Never";
    };
    mapServerImage = {
      name = "map-server";
      tag = "latest";
      pullPolicy = "Never";
    };
    resources = {
      limits = {
        memory = "1Gi";
        cpu = "1000m";
      };
      requests = {
        memory = "512Mi";
        cpu = "250m";
      };
    };
    ports = {
      kwaainet = 8080;
      mapServer = 3030;
    };
  };
}
