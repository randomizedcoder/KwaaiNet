# Kubernetes Deployment manifest for KwaaiNet.
# Deploys kwaainet + map-server as a single pod.
{ pkgs, constants }:
let
  k = constants.k8s;
  yaml = ''
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: ${k.deploymentName}
      namespace: ${k.namespace}
      labels:
        app: ${k.labels.app}
        component: ${k.labels.component}
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: ${k.labels.app}
      template:
        metadata:
          labels:
            app: ${k.labels.app}
            component: ${k.labels.component}
        spec:
          containers:
            - name: kwaainet
              image: ${k.image.name}:${k.image.tag}
              imagePullPolicy: ${k.image.pullPolicy}
              args:
                - "start"
                - "--port"
                - "${toString k.ports.kwaainet}"
                - "--no-gpu"
                - "--blocks"
                - "8"
              ports:
                - containerPort: ${toString k.ports.kwaainet}
                  name: p2p
                  protocol: TCP
              resources:
                limits:
                  memory: ${k.resources.limits.memory}
                  cpu: ${k.resources.limits.cpu}
                requests:
                  memory: ${k.resources.requests.memory}
                  cpu: ${k.resources.requests.cpu}
            - name: map-server
              image: ${k.mapServerImage.name}:${k.mapServerImage.tag}
              imagePullPolicy: ${k.mapServerImage.pullPolicy}
              env:
                - name: BIND_ADDR
                  value: "0.0.0.0:${toString k.ports.mapServer}"
                - name: TOTAL_BLOCKS
                  value: "80"
                - name: ALLOWED_ORIGINS
                  value: "*"
              ports:
                - containerPort: ${toString k.ports.mapServer}
                  name: http
                  protocol: TCP
              readinessProbe:
                httpGet:
                  path: /health
                  port: ${toString k.ports.mapServer}
                initialDelaySeconds: 5
                periodSeconds: 10
              resources:
                limits:
                  memory: "256Mi"
                  cpu: "250m"
                requests:
                  memory: "128Mi"
                  cpu: "100m"
  '';
in
{
  inherit yaml;
  file = pkgs.writeText "kwaainet-deployment.yaml" yaml;
}
