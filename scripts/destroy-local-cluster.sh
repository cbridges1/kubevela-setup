#!/usr/bin/env bash
set -euo pipefail

# Tears down the k3d cluster scripts/create-local-cluster.sh made. Safe to
# run even if it doesn't exist. Your other kubectl contexts are untouched.

CLUSTER_NAME="${1:-kubevela-local}"

log() { echo "── $*"; }

if k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1; then
  log "Deleting k3d cluster '$CLUSTER_NAME'"
  k3d cluster delete "$CLUSTER_NAME"
else
  log "k3d cluster '$CLUSTER_NAME' doesn't exist — nothing to do"
fi
