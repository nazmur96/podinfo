# podinfo

[![e2e](https://github.com/stefanprodan/podinfo/workflows/e2e/badge.svg)](https://github.com/stefanprodan/podinfo/blob/master/.github/workflows/e2e.yml)
[![test](https://github.com/stefanprodan/podinfo/workflows/test/badge.svg)](https://github.com/stefanprodan/podinfo/blob/master/.github/workflows/test.yml)
[![cve-scan](https://github.com/stefanprodan/podinfo/workflows/cve-scan/badge.svg)](https://github.com/stefanprodan/podinfo/blob/master/.github/workflows/cve-scan.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/stefanprodan/podinfo)](https://hub.docker.com/r/stefanprodan/podinfo)
[![slsa](https://slsa.dev/images/gh-badge-level2.svg)](https://github.com/stefanprodan/podinfo/attestations)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/stefanprodan/podinfo)

Podinfo is a tiny web application made with Go that showcases best practices of running microservices in Kubernetes.
Podinfo is used by CNCF projects like [Flux](https://github.com/fluxcd/flux2) and [Flagger](https://github.com/fluxcd/flagger)
for end-to-end testing and workshops.

Specifications:

* Health checks (readiness and liveness)
* Graceful shutdown on interrupt signals
* File watcher for secrets and configmaps
* Instrumented with Prometheus and Open Telemetry
* Structured logging with zap
* 12-factor app with viper
* Fault injection (random errors and latency)
* Swagger docs
* Timoni, Helm and Kustomize installers
* End-to-End testing with Kubernetes Kind and Helm
* Multi-arch container image with Docker buildx and GitHub Actions
* Container image signing with Sigstore cosign
* SBOMs and SLSA Provenance embedded in the container image
* CVE scanning with govulncheck

Web API:

* `GET /` prints runtime information
* `GET /version` prints podinfo version and git commit hash
* `GET /metrics` return HTTP requests duration and Go runtime metrics
* `GET /healthz` used by Kubernetes liveness probe
* `GET /readyz` used by Kubernetes readiness probe
* `POST /readyz/enable` signals the Kubernetes LB that this instance is ready to receive traffic
* `POST /readyz/disable` signals the Kubernetes LB to stop sending requests to this instance
* `POST /fault_injection/enable` makes this instance respond with HTTP 500 to all application endpoints (probes, metrics, pprof and the `/fault_injection/*` control endpoints stay healthy) — useful for testing client-side circuit breakers / outlier detection against a single "sick" replica
* `POST /fault_injection/disable` restores normal responses
* `GET /fault_injection/status` returns the current fault injection state (`enabled` or `disabled`)
* `GET /status/{code}` returns the status code
* `GET /panic` crashes the process with exit code 255
* `POST /echo` forwards the call to the backend service and echos the posted content
* `GET /env` returns the environment variables as a JSON array
* `GET /headers` returns a JSON with the request HTTP headers
* `GET /delay/{seconds}` waits for the specified period
* `POST /token` issues a JWT token valid for one minute `JWT=$(curl -sd 'anon' podinfo:9898/token | jq -r .token)`
* `GET /token/validate` validates the JWT token `curl -H "Authorization: Bearer $JWT" podinfo:9898/token/validate`
* `GET /configs` returns a JSON with configmaps and/or secrets mounted in the `config` volume
* `POST/PUT /cache/{key}` saves the posted content to Redis
* `GET /cache/{key}` returns the content from Redis if the key exists
* `DELETE /cache/{key}` deletes the key from Redis if exists
* `POST /store` writes the posted content to disk at /data/hash and returns the SHA1 hash of the content
* `GET /store/{hash}` returns the content of the file /data/hash if exists
* `GET /ws/echo` echos content via websockets `podcli ws ws://localhost:9898/ws/echo`
* `GET /chunked/{seconds}` uses `transfer-encoding` type `chunked` to give a partial response and then waits for the specified period
* `GET /swagger.json` returns the API Swagger docs, used for Linkerd service profiling and Gloo routes discovery

gRPC API:

* `/grpc.health.v1.Health/Check` health checking
* `/grpc.EchoService/Echo` echos the received content
* `/grpc.VersionService/Version` returns podinfo version and Git commit hash
* `/grpc.DelayService/Delay` returns a successful response after the given seconds in the body of gRPC request
* `/grpc.EnvService/Env` returns environment variables as a JSON array
* `/grpc.HeaderService/Header` returns the headers present in the gRPC request. Any custom header can also be given as a part of request and that can be returned using this API
* `/grpc.InfoService/Info` returns the runtime information
* `/grpc.PanicService/Panic` crashes the process with gRPC status code as '1 CANCELLED'
* `/grpc.StatusService/Status` returns the gRPC Status code given in the request body
* `/grpc.TokenService/TokenGenerate` issues a JWT token valid for one minute
* `/grpc.TokenService/TokenValidate` validates the JWT token

Web UI:

![podinfo-ui](https://raw.githubusercontent.com/stefanprodan/podinfo/gh-pages/screens/podinfo-ui-v3.png)

To access the Swagger UI open `<podinfo-host>/swagger/index.html` in a browser.

### Platform docs

This fork is deployed by a learning platform project. Ownership contract (image tags, deploy gates, prod approval, rollback, manifest owner): [ownership.md](https://github.com/nazmur96/podinfo-platform/blob/main/docs/ownership.md) · service manifest: [MANIFEST.md](https://github.com/nazmur96/podinfo/blob/master/MANIFEST.md) · conventions: [conventions.md](https://github.com/nazmur96/podinfo-platform/blob/main/docs/conventions.md)

### Dev toolchain

Go **1.27.0** is owned by [`mise.toml`](mise.toml) in this repo. Do not install a project Go on the host. Do not add `devenv.nix` here.

**Userland** + docker-in-docker (for image builds in P2): [`.devcontainer/`](.devcontainer/).
**gopls** runs in the container (editor server), not on the host.

```bash
devpod up . --provider docker
# or: mise trust && mise install
```

### Run locally (no image)

Upstream's README jumps to Docker/Helm, but its `Makefile` has the
developers' path. Run it inside the dev container (`make` isn't on the host):

```bash
make run          # :9898, gRPC :9999, --level=debug, commit stamped via git describe
```

`make run` also sets two `--backend-url`s at `httpbin.org`, so `POST /echo`
calls the internet. For a bare start with defaults:

```bash
mise exec -- go run ./cmd/podinfo --port=9898
```

Then `curl -sS http://127.0.0.1:9898/healthz`. Flags are also env vars with
prefix `PODINFO_` (hyphens → underscores), e.g. `PODINFO_PORT=9898`,
`PODINFO_JWT_SECRET=…`. `/version`'s `commit` is whatever the build stamps
into `pkg/version.REVISION`: `git describe` with `make run`, `unknown` with a
plain `go run`, and the full SHA from CI (`--build-arg REVISION`, CUJ step 1).

### Fork patch: `--enable-unsafe-endpoints` (ADR-0006, ADR-0008)

**Default off.** When off, these routes are not registered (HTTP 404):

`/env`, `/configs`, `/debug/pprof/`, `/panic`, `/delay/{n}`, `/chunked`,
`/store`, `/fault_injection/*`, `/readyz/enable`, `/readyz/disable`.

The same flag gates the gRPC `Env`, `Panic` and `Delay` services, and the
metrics port (`--port-metrics`) never serves the Go profiler: it has its own
router (upstream served `http.DefaultServeMux` there, where `net/http/pprof`
registers `/debug/pprof/`).

Turn on only for local experiments:

```bash
mise exec -- go run ./cmd/podinfo --port=9898 --enable-unsafe-endpoints
# or: PODINFO_ENABLE_UNSAFE_ENDPOINTS=true
```

Deployed environments must leave this flag off. Fault drills use startup
flags (`--random-error`, etc.) via gitops, not runtime HTTP toggles.

### Fork patch: errors carry their HTTP status (P2-8)

Upstream's `ErrorResponse` always wrote HTTP **200** and put the real code
only in the JSON body, so a bad token "succeeded" with 200. Ours sends the
code as the status (400, 401, 413, 500). Successful responses are unchanged.

### Container image (P2-1)

Our `Dockerfile` (not upstream's): multi-stage →
`gcr.io/distroless/static-debian12:nonroot`, **numeric** `USER 65532`, no
shell / `curl` / `netcat` / `podcli`. Listen on **9898**.

```bash
docker build -t podinfo:local --build-arg REVISION=$(git rev-parse HEAD) .
docker run --rm -p 9898:9898 podinfo:local
docker inspect -f '{{.Config.User}}' podinfo:local   # 65532:65532
```

### Hardening audit (P2-4)

Against `podinfo:local` built from this tree:

| Check | Result |
|---|---|
| Non-root | `docker inspect` → `65532:65532` |
| Digests | Both `FROM` lines pin `@sha256:…`; no `latest` |
| hadolint | Clean |
| dive | **99.999%** efficiency; layers hold only the distroless base, the binary and `ui/`. No `.git`, sources, tests or keys |
| Dockle | No warnings. Two INFO notes, both deliberate: no `HEALTHCHECK` (no shell; Kubernetes probes do it), and content trust (cosign in P7) |
| Trivy `HIGH,CRITICAL --ignore-unfixed` | Zero after bumping `golang.org/x/net` to **v0.60.0** (clears CVE-2026-78669) |
| Listeners | Main `:9898`, metrics `:9797`, gRPC `:9999` — gated HTTP routes and `/debug/pprof/*` are **404** on 9898 and 9797; gRPC `Env`/`Panic`/`Delay` are absent from `grpcurl list` |
| Read-only root | `--read-only --cap-drop ALL --security-opt no-new-privileges`, no writable mounts: CUJ 1–6 and the web UI work. `/store` (flag on) needs a writable `/data` (the image passes `--data-path=/data`; `tmpfs`/`emptyDir` there); without it the write fails with 500. Nothing needs `/tmp` |

P6: `readOnlyRootFilesystem: true` plus an `emptyDir` on `/data` only if `/store` is ever enabled; no `/tmp` volume required for v1.

### Compose, size budget and the CUJ (P2-5, P2-7, P2-8)

`compose.yaml` runs the image the way Kubernetes will: read-only root, all
capabilities dropped, `no-new-privileges`, and the JWT secret mounted as
`/config/config.yaml` (ADR-0006). Tools come from `mise.toml`.

```bash
scripts/make-local-secret.sh                          # once: .secrets/config.yaml (git- and docker-ignored)
REVISION=$(git rev-parse HEAD) docker compose up --build -d
EXPECT_SHA=$(git rev-parse HEAD) mise exec -- scripts/cuj.sh
mise exec -- scripts/check-image-size.sh podinfo:local 30
docker compose down
```

- `scripts/cuj.sh` runs the 8 CUJ steps (platform `docs/cuj.md`) and exits
  non-zero if any fails. Read the `FAIL` lines: each says what it got and
  what it wanted. `BASE=` points it elsewhere (kind, EKS); `STEP7=skip` only
  where the real secret isn't wired (a bare `make run`).
- `scripts/check-image-size.sh <image> <MiB>` compares **bytes** of the
  unpacked image (`docker image inspect .Size`), so 30.9 MiB fails a 30 MiB
  budget. Budget for this Go image: **30 MiB**. Blocking in CI from P7.
- No Compose healthcheck: the image has no shell or `curl` to run one.
  `cuj.sh` waits for `/readyz`; Kubernetes probes from outside (P3).

### Local kind cluster (P3-1)

Runs on the **host's Docker** with tools from this repo's `mise.toml`
(ADR-0011). The kubeconfig is `.kube/config` in the repo (git-ignored), not
`~/.kube/config`. Node image and kubectl minor match EKS (ADR-0010).

```bash
mise install
mise exec -- scripts/cluster-up.sh          # 3 control planes + 3 workers (no app yet)
scripts/make-local-secret.sh                # once: .secrets/config.yaml
mise exec -- scripts/deploy.sh              # build → kind load → Secret → apply k8s/overlays/dev
EXPECT_SHA=$(git rev-parse HEAD) \
  bash -c 'mise exec -- kubectl -n podinfo-dev port-forward svc/podinfo 9898:80 &
           sleep 2; EXPECT_SHA=$(git rev-parse HEAD) mise exec -- scripts/cuj.sh; kill %1'
mise exec -- scripts/check-labels.sh
mise exec -- scripts/cluster-down.sh
```

Namespace `podinfo-dev` (PSA restricted) is owned by `k8s/base/namespace.yaml`
and created on deploy — not by `kind/`. Host ports 80/443 map to NodePorts
30080/30443 for the P3-6 Gateway. Do not `devpod up` from a git worktree.
Do not add an IPv6 `listenAddress` on those mappings (see `kind/cluster.yaml`).

### Guides

* [Getting started with Timoni](https://timoni.sh/quickstart/)
* [Getting started with Flux](https://fluxcd.io/flux/get-started/)
* [Progressive Deliver with Flagger and Linkerd](https://docs.flagger.app/tutorials/linkerd-progressive-delivery)
* [Automated canary deployments with Kubernetes Gateway API](https://docs.flagger.app/tutorials/gatewayapi-progressive-delivery)

### Install

To install Podinfo on Kubernetes the minimum required version is **Kubernetes v1.23**.

#### Timoni

Install with [Timoni](https://timoni.sh):

```bash
timoni -n default apply podinfo oci://ghcr.io/stefanprodan/modules/podinfo
```

#### Helm

Install from github.io:

```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo

helm upgrade --install --wait frontend \
--namespace test \
--set replicaCount=2 \
--set backend=http://backend-podinfo:9898/echo \
podinfo/podinfo

helm test frontend --namespace test

helm upgrade --install --wait backend \
--namespace test \
--set redis.enabled=true \
podinfo/podinfo
```

Install from ghcr.io:

```bash
helm upgrade --install --wait podinfo --namespace default \
oci://ghcr.io/stefanprodan/charts/podinfo
```

#### Kustomize

```bash
kubectl apply -k github.com/stefanprodan/podinfo//kustomize
```

#### Docker

```bash
docker run -dp 9898:9898 stefanprodan/podinfo
```

### Continuous Delivery

In order to install podinfo on a Kubernetes cluster and keep it up to date with the latest
release in an automated manner, you can use [Flux](https://fluxcd.io).

Install the Flux CLI on MacOS and Linux using Homebrew:

```sh
brew install fluxcd/tap/flux
```

Install the Flux controllers needed for Helm operations:

```sh
flux install \
--namespace=flux-system \
--network-policy=false \
--components=source-controller,helm-controller
```

Add podinfo's Helm repository to your cluster and
configure Flux to check for new chart releases every ten minutes:

```sh
flux create source helm podinfo \
--namespace=default \
--url=https://stefanprodan.github.io/podinfo \
--interval=10m
```

Create a `podinfo-values.yaml` file locally:

```sh
cat > podinfo-values.yaml <<EOL
replicaCount: 2
resources:
  limits:
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 64Mi
EOL
```

Create a Helm release for deploying podinfo in the default namespace:

```sh
flux create helmrelease podinfo \
--namespace=default \
--source=HelmRepository/podinfo \
--release-name=podinfo \
--chart=podinfo \
--chart-version=">5.0.0" \
--values=podinfo-values.yaml
```

Based on the above definition, Flux will upgrade the release automatically
when a new version of podinfo is released. If the upgrade fails, Flux
can [rollback](https://toolkit.fluxcd.io/components/helm/helmreleases/#configuring-failure-remediation)
to the previous working version.

You can check what version is currently deployed with:

```sh
flux get helmreleases -n default
```

To delete podinfo's Helm repository and release from your cluster run:

```sh
flux -n default delete source helm podinfo
flux -n default delete helmrelease podinfo
```

If you wish to manage the lifecycle of your applications in a **GitOps** manner, check out
this [workflow example](https://github.com/fluxcd/flux2-kustomize-helm-example)
for multi-env deployments with Flux, Kustomize and Helm.
