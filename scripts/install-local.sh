#!/usr/bin/env bash
set -euo pipefail

# Builds vela-core from a local kubevela/kubevela checkout (KUBEVELA_SRC, see
# below — NOT a published oamdev/vela-core release, so uncommitted
# work-in-progress is actually what gets deployed) and installs it onto
# whatever cluster your current kubectl context points at — run
# scripts/create-local-cluster.sh first.
#
# This repo (kubevela-setup) is deliberately just tooling: it doesn't vendor
# or fork kubevela's source. Point it at your own kubevela checkout (a fork
# you're developing against) via KUBEVELA_SRC, or let it default to a
# sibling directory named `kubevela` next to this repo, e.g.:
#
#   Source/misc/kubevela-setup   <- this repo
#   Source/misc/kubevela         <- your kubevela checkout (default)
#
# Uses kubevela's OWN Dockerfile (the one at the root of that checkout) as
# the build — that Dockerfile already builds cmd/core/main.go from local
# source into an alpine image, so there's no separate "dev" Dockerfile to
# maintain here; it just needs a build context pointing at your checkout.
#
# Like scripts/install-local.sh in other repos of this shape, this does NOT
# clean up after itself — it's meant to leave a running install behind.
# Re-running it is safe/idempotent (helm upgrade --install, kubectl apply,
# CRDs applied separately since `helm upgrade` does not update CRDs once
# installed).
#
# Usage: scripts/install-local.sh [namespace] [release-name]
#   namespace      defaults to vela-system
#   release-name   defaults to kubevela

NAMESPACE="${1:-vela-system}"
RELEASE_NAME="${2:-kubevela}"
IMAGE_REPO="vela-core"
IMAGE_TAG="dev"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBEVELA_SRC="${KUBEVELA_SRC:-$ROOT_DIR/../kubevela}"

log() { echo "── $*"; }
fail() { echo "✖ $*" >&2; exit 1; }

[[ -d "$KUBEVELA_SRC" ]] || fail "KUBEVELA_SRC not found at '$KUBEVELA_SRC'. Clone your kubevela checkout there, or set KUBEVELA_SRC=/path/to/kubevela."
[[ -f "$KUBEVELA_SRC/Dockerfile" && -d "$KUBEVELA_SRC/charts/vela-core" ]] || fail "'$KUBEVELA_SRC' doesn't look like a kubevela checkout (missing Dockerfile / charts/vela-core)."

GIT_COMMIT="$(git -C "$KUBEVELA_SRC" rev-parse --short HEAD 2>/dev/null || echo dev)"

# Same reasoning as other repos of this shape: the image build/run platform
# here is independent of what the *cluster* runs — Kubernetes pulls images
# via containerd, not this shell's `docker` CLI — so this is passed
# explicitly rather than relying on DOCKER_DEFAULT_PLATFORM being sane.
DOCKER_PLATFORM="linux/$(docker version --format '{{.Server.Arch}}')"

log "Building $IMAGE_REPO:$IMAGE_TAG from $KUBEVELA_SRC (commit $GIT_COMMIT, platform $DOCKER_PLATFORM)"
docker build --platform "$DOCKER_PLATFORM" --load \
  -f "$KUBEVELA_SRC/Dockerfile" \
  --build-arg VERSION=dev \
  --build-arg GITVERSION="$GIT_COMMIT" \
  -t "$IMAGE_REPO:$IMAGE_TAG" \
  "$KUBEVELA_SRC"

# k3d nodes run their own containerd, entirely separate from the host
# Docker daemon's image store — `docker build --load` alone does NOT make
# the image visible inside a k3d cluster. Without this, kubelet tries to
# pull "vela-core:dev" from Docker Hub (where it doesn't exist) and every
# pod ErrImagePulls. `k3d image import` copies the image directly into the
# cluster's containerd, no registry involved. Skipped when the current
# context isn't a k3d cluster.
CURRENT_CONTEXT="$(kubectl config current-context)"
if [[ "$CURRENT_CONTEXT" == k3d-* ]]; then
  K3D_CLUSTER="${CURRENT_CONTEXT#k3d-}"
  log "Importing $IMAGE_REPO:$IMAGE_TAG into k3d cluster '$K3D_CLUSTER'"
  k3d image import "$IMAGE_REPO:$IMAGE_TAG" -c "$K3D_CLUSTER"
fi

log "Ensuring namespace $NAMESPACE exists"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# helm only installs CRDs from a chart's crds/ directory on first install —
# it never updates them on `helm upgrade`. Applying them directly every run
# is what actually keeps CRDs (new fields, new definitions, etc.) in sync
# with whatever's on disk in your checkout.
log "Applying CRDs from $KUBEVELA_SRC/charts/vela-core/crds"
kubectl apply -f "$KUBEVELA_SRC/charts/vela-core/crds/" >/dev/null

# :dev is a floating tag this script overwrites every run, so IfNotPresent +
# a rollout restart alone wouldn't guarantee the freshest content gets used
# on a cluster that already had it — except k3d's own containerd is what
# `k3d image import` just fully replaced the tag's local content in, so
# IfNotPresent (skip anything that would touch a real registry) is correct
# here. Always would be actively wrong against a k3d cluster: it'd try to
# verify "vela-core:dev" against docker.io, find no such repository, and
# ErrImagePullBackOff even though a perfectly good image already sits in
# containerd.
if [[ "$CURRENT_CONTEXT" == k3d-* ]]; then
  PULL_POLICY="IfNotPresent"
else
  PULL_POLICY="Always"
fi

log "Installing $RELEASE_NAME (chart: $KUBEVELA_SRC/charts/vela-core, image.pullPolicy=$PULL_POLICY)"
helm upgrade --install "$RELEASE_NAME" "$KUBEVELA_SRC/charts/vela-core" \
  --namespace "$NAMESPACE" --create-namespace \
  --set image.repository="$IMAGE_REPO" \
  --set image.tag="$IMAGE_TAG" \
  --set image.pullPolicy="$PULL_POLICY" >/dev/null

log "Restarting the vela-core Deployment so the freshly-built image is actually used"
kubectl -n "$NAMESPACE" rollout restart deployment -l controller.oam.dev/name=vela-core

log "Waiting for rollout"
kubectl -n "$NAMESPACE" rollout status deployment -l controller.oam.dev/name=vela-core --timeout=120s

echo ""
echo "✅ Installed. vela-core running in namespace '$NAMESPACE' from $KUBEVELA_SRC (commit $GIT_COMMIT)."
echo ""
echo "Next steps:"
echo ""
echo "  1. Build a local vela CLI matching this checkout:"
echo "     scripts/build-vela-cli.sh"
echo ""
echo "  2. Smoke-test with a trivial Application:"
echo "     cat <<'EOF' | kubectl apply -f -"
echo "     apiVersion: core.oam.dev/v1beta1"
echo "     kind: Application"
echo "     metadata:"
echo "       name: smoke-test"
echo "       namespace: default"
echo "     spec:"
echo "       components:"
echo "         - name: hello"
echo "           type: webservice"
echo "           properties:"
echo "             image: nginx:alpine"
echo "     EOF"
echo "     bin/vela status smoke-test   # (after step 1) or: kubectl get application smoke-test -o yaml"
echo ""
echo "  3. Tail the controller logs:"
echo "     kubectl -n $NAMESPACE logs -l controller.oam.dev/name=vela-core -f"
