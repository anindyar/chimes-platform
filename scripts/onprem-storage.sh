#!/usr/bin/env bash
# Bare RKE2 ships no StorageClass at all — every PVC in the platform would sit
# Pending. Managed clusters do not need this script.
#
# local-path-provisioner is node-local: fine for a single-node management or
# demo cluster, NOT the answer for the customer's multi-node on-prem cluster,
# which should use their existing CSI (Longhorn, vSphere, NetApp, Ceph...).
# Whatever they use, the platform chart only ever receives its NAME.
set -euo pipefail

VERSION="${VERSION:-v0.0.32}"
KUBECTL="${KUBECTL:-kubectl}"

$KUBECTL apply -f "https://raw.githubusercontent.com/rancher/local-path-provisioner/${VERSION}/deploy/local-path-storage.yaml"
$KUBECTL -n local-path-storage rollout status deploy/local-path-provisioner --timeout=120s
$KUBECTL patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
$KUBECTL get storageclass
