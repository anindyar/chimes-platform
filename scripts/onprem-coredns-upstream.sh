#!/usr/bin/env bash
# CoreDNS forwards to the NODE's /etc/resolv.conf by default. On any node that
# runs Tailscale with accept-dns on, that file points at the MagicDNS resolver
# 100.100.100.100, which is reachable from the host but NOT from the pod
# network — so every in-cluster lookup of an external name fails with
# "server misbehaving" / i/o timeout while the node itself resolves fine.
#
# Symptom it causes: model/chart/image pulls made BY a pod fail, but
# containerd image pulls (which use the node's resolver) succeed, so the
# cluster looks half-broken for no obvious reason.
#
# Fix: forward to real upstream resolvers instead of the node's resolv.conf.
# Applied as a HelmChartConfig because RKE2 manages CoreDNS with the Helm
# controller and will revert a hand-edited ConfigMap on the next restart.
set -euo pipefail

UPSTREAMS="${UPSTREAMS:-192.168.0.1 1.1.1.1}"
MANIFEST=/var/lib/rancher/rke2/server/manifests/rke2-coredns-config.yaml

sudo tee "$MANIFEST" >/dev/null <<YAML
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-coredns
  namespace: kube-system
spec:
  valuesContent: |-
    servers:
      - zones:
          - zone: .
        port: 53
        plugins:
          - name: errors
          - name: health
            configBlock: |-
              lameduck 10s
          - name: ready
          - name: kubernetes
            parameters: cluster.local in-addr.arpa ip6.arpa
            configBlock: |-
              pods insecure
              fallthrough in-addr.arpa ip6.arpa
              ttl 30
          - name: prometheus
            parameters: 0.0.0.0:9153
          - name: forward
            parameters: . ${UPSTREAMS}
          - name: cache
            parameters: 30
          - name: loop
          - name: reload
          - name: loadbalance
YAML

echo "wrote $MANIFEST — waiting for the helm controller to reconcile"
for _ in $(seq 1 30); do
  if kubectl -n kube-system get cm rke2-coredns-rke2-coredns -o jsonpath='{.data.Corefile}' | grep -q "forward . ${UPSTREAMS%% *}"; then
    echo "Corefile updated"; break
  fi
  sleep 5
done
kubectl -n kube-system rollout restart deploy/rke2-coredns-rke2-coredns
kubectl -n kube-system rollout status deploy/rke2-coredns-rke2-coredns --timeout=120s
