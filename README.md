# kubevela-setup

Local k3d dev loop for [kubevela/kubevela](https://github.com/kubevela/kubevela): build vela-core from a
local checkout, run it in a real cluster, iterate. Same shape as this
machine's other `*-setup`/local-dev repos (see `hyve`) — this repo is just
tooling, it doesn't vendor or fork KubeVela's source.

## Layout

This repo expects your KubeVela checkout (a fork you're developing against)
to live as a sibling directory by default:

```
Source/misc/kubevela-setup/   <- this repo
Source/misc/kubevela/         <- your kubevela checkout (default KUBEVELA_SRC)
```

Point somewhere else instead with `KUBEVELA_SRC=/path/to/kubevela`.

## Prerequisites

- [k3d](https://k3d.io) (wraps k3s in Docker)
- Docker
- kubectl, [Helm](https://helm.sh) 3
- Go (only needed for `build:cli`, to compile the `vela`/`kubectl-vela` CLIs)

## Quickstart

```bash
task cluster:local     # create the k3d cluster, once
task install:local     # build vela-core from KUBEVELA_SRC, deploy it
task build:cli         # optional: compile `vela`/`kubectl-vela` into ./bin
```

Or without `task` (a [Taskfile](https://taskfile.dev) is included, but every
task is a thin wrapper — the scripts work standalone):

```bash
scripts/create-local-cluster.sh
scripts/install-local.sh
scripts/build-vela-cli.sh
```

`install:local` is safe to re-run any time you change something in
`KUBEVELA_SRC`: it rebuilds the image, re-imports it into k3d, re-applies
CRDs, and restarts the controller so the new build actually gets picked up.
It leaves a running install behind — it's not a self-cleaning smoke test.

## Why a dedicated k3d cluster

Docker Desktop's own built-in Kubernetes only maps its fixed API-server
port to the host — NodePort and LoadBalancer services aren't reachable from
outside it. `create-local-cluster.sh` instead creates a standalone k3d
cluster with host `80`/`443` mapped to k3d's own load balancer container at
creation time (the only point k3d/kind let you set a port mapping at all).
k3d ships Traefik as its default ingress controller listening behind that
load balancer, so exposing something later — VelaUX, the apiserver, an
Ingress on one of your own Applications — is just an Ingress resource, no
cluster change.

## How install-local.sh actually deploys your code

- Builds the image with KubeVela's own root `Dockerfile` — that Dockerfile
  already builds `cmd/core/main.go` from whatever's on disk in
  `KUBEVELA_SRC`, so there's no separate "dev" Dockerfile to maintain here.
- `k3d image import`s it directly into the cluster's containerd — k3d nodes
  don't share the host Docker daemon's image store, so `docker build` alone
  wouldn't make the image visible to kubelet.
- Applies `charts/vela-core/crds/` directly with `kubectl apply` before the
  Helm install — Helm only installs CRDs from a chart's `crds/` folder on
  first install, never on `helm upgrade`, so this is what actually keeps
  CRDs in sync with your checkout across iterations.
- `helm upgrade --install`s `charts/vela-core` itself (KubeVela's real chart,
  used as-is, not copied into this repo) pointed at the freshly-imported
  image, then restarts the Deployment so a floating `:dev` tag doesn't get
  skipped by `imagePullPolicy: IfNotPresent`.

Admission webhooks are on by default in that chart
(`admissionWebhooks.enabled: true`) and self-provision their own TLS via the
bundled `kube-webhook-certgen` job — no cert-manager needed for this to
work out of the box.

## Debugging the controller outside the cluster

For fast webhook/controller debugging without an image build at all,
KubeVela's own Makefile already ships `make k3d-create`,
`make webhook-debug-setup`, etc. (see `makefiles/develop.mk` in
`KUBEVELA_SRC`) — that flow runs the controller as a local `go run` process
against a k3d cluster that only holds CRDs, with the webhook tunneled back
to your machine. Reach for that when you're stepping through code in a
debugger; reach for this repo's `install:local` when you want to see how it
actually behaves fully in-cluster (RBAC, real webhook TLS, restarts,
resource limits, etc.) before opening a PR.

## Troubleshooting

- **`ErrImagePullBackOff` on vela-core** — almost always means the current
  kubectl context isn't actually a `k3d-*` context (so the image never got
  imported) or you switched clusters after building. Check
  `kubectl config current-context`.
- **CRD changes not showing up** — re-run `install-local.sh`; it always
  re-applies `charts/vela-core/crds/` from `KUBEVELA_SRC`.
- **Stale controller after a rebuild** — the script always does an explicit
  `rollout restart`, but if you're impatient: `kubectl -n vela-system get
  pods -l controller.oam.dev/name=vela-core` to confirm a new pod actually
  started.

## Teardown

```bash
task cluster:destroy
```
