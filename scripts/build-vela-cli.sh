#!/usr/bin/env bash
set -euo pipefail

# Builds the `vela` and `kubectl-vela` binaries straight from KUBEVELA_SRC
# using kubevela's own Makefile targets (vela-cli / kubectl-vela), so
# whatever CLI flags/behavior your checkout currently has is what you get —
# not whatever's on your PATH from a package manager. Copies both into this
# repo's bin/ (gitignored) so they don't get lost inside KUBEVELA_SRC.
#
# Usage: scripts/build-vela-cli.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBEVELA_SRC="${KUBEVELA_SRC:-$ROOT_DIR/../kubevela}"

log() { echo "── $*"; }
fail() { echo "✖ $*" >&2; exit 1; }

[[ -d "$KUBEVELA_SRC" ]] || fail "KUBEVELA_SRC not found at '$KUBEVELA_SRC'. Clone your kubevela checkout there, or set KUBEVELA_SRC=/path/to/kubevela."

log "Building vela + kubectl-vela from $KUBEVELA_SRC"
make -C "$KUBEVELA_SRC" vela-cli kubectl-vela

mkdir -p "$ROOT_DIR/bin"
cp "$KUBEVELA_SRC/bin/vela" "$ROOT_DIR/bin/vela"
cp "$KUBEVELA_SRC/bin/kubectl-vela" "$ROOT_DIR/bin/kubectl-vela"

echo ""
echo "✅ Built $ROOT_DIR/bin/vela and $ROOT_DIR/bin/kubectl-vela"
echo ""
echo "Add this repo's bin/ to your PATH, or run directly:"
echo "  $ROOT_DIR/bin/vela status <app-name>"
