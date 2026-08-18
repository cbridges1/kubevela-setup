#!/usr/bin/env bash
set -euo pipefail

# Creates (idempotently) a standalone k3d cluster named kubevela-local for
# local KubeVela core development — separate from Docker Desktop's own
# built-in Kubernetes, which doesn't expose any way to map host ports beyond
# its fixed API-server port, and separate from any other cluster you use for
# real work.
#
# One server + one agent (matches the shape kubevela/kubevela's own
# Makefile uses for its `k3d-create` webhook-debug target), plus host 80/443
# mapped to k3d's load balancer container — done once, at creation time,
# since neither k3d nor kind support adding a port mapping to a running
# cluster. k3d ships Traefik as its default ingress controller already
# listening behind that load balancer, so exposing VelaUX or the apiserver
# later (see charts/vela-core's ingress-shaped values, e.g. under
# `servicetype`/`ingress` for various components) is just an Ingress
# resource — no new port to pick, no cluster change, ever again.
#
# Sets your kubectl context to this cluster when done. Any other context
# (Docker Desktop, a real cluster, etc.) is untouched and still switchable
# back to.

CLUSTER_NAME="${1:-kubevela-local}"

log() { echo "── $*"; }

if k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1; then
  log "k3d cluster '$CLUSTER_NAME' already exists — leaving it as-is"
else
  log "Creating k3d cluster '$CLUSTER_NAME' (1 server + 1 agent, host 80/443 -> loadbalancer -> Traefik)"
  k3d cluster create "$CLUSTER_NAME" \
    --servers 1 \
    --agents 1 \
    -p "80:80@loadbalancer" \
    -p "443:443@loadbalancer" \
    --wait
fi

kubectl config use-context "k3d-$CLUSTER_NAME" >/dev/null
log "kubectl context set to k3d-$CLUSTER_NAME"

echo ""
echo "✅ Cluster ready. Next: task install:local (or scripts/install-local.sh)"
