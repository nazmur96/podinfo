# SERVICE MANIFEST: podinfo

P0-2b. Values checked against the code at `3e0ff8a` (tag `6.15.0`). This is an open-source
fork with no dev lead, so answers come from code, and decisions are marked
`ADR pending` until recorded. Inventory and open questions:
https://github.com/nazmur96/podinfo-platform/tree/main/docs (private).

## 1. Identity
- Runtime: Go 1.27 (`go.mod`), static binary (`CGO_ENABLED=0`)
- Artifact: upstream `Dockerfile` (`golang:1.27-alpine` → `alpine:3.24`). We replace/harden it in P2:
  it runs as non-numeric `USER app` (fails `runAsNonRoot`) and ships `curl` + `netcat`
- Multi-arch: upstream builds amd64+arm64. Lean amd64-only for first CI — ADR pending

## 2. Network
- Exposure: ClusterIP until P9, then public via ALB/Gateway
- Port: HTTP **9898** (`--port`, `cmd/podinfo/main.go:34`)
- Also serving: metrics **9797** when `--port-metrics` is set (binary default `0` = off)
- `/metrics` is **also always on 9898** (`pkg/api/http/server.go:138`), so it is public unless the HTTPRoute filters it
- Not exposing for v1: gRPC 9999, HTTPS-in-pod 9899 (both off by default in the binary)
- Protocol: HTTP/1.1 (h2c off). Also serves websockets (`/ws/echo`) and chunked responses. TLS terminates at the ALB
- Fixed IP / mTLS to clients: no
- Unauthenticated control endpoints to keep off the internet: `/env`, `/panic`,
  `/fault_injection/*`, `/readyz/enable|disable`, `/store`, `/delay/{s}`, `/token`,
  `/debug/pprof/` (Go profiler, always routed on 9898, `pkg/api/http/server.go:139`)

## 3. Compute
- CPU/RAM: unknown. Measure in P3; do not trust the chart (`1m`/`16Mi`) or kustomize (`100m`/`64Mi` → `2000m`/`512Mi`)
- Stateless: yes for our CUJ. **But** `POST /store` is always routed and writes to `/data`
  (`--data-path`). We use emptyDir: lost on restart, different per replica, no PVC
- Min/max replicas: start with 2; final numbers in P6 (prod floor ≥ 2)
- Scaling signal: CPU or HTTP RPS — confirm under load in P6

## 4. Data
- Engine: none for v1
- Redis: optional, **not in v1**. Only `/cache/*` uses it
- Single/Multi-AZ, peak connections: N/A in v1. If Redis is added: the pool sets
  `MaxIdle: 3` and no `MaxActive`, so connections are **unbounded** under load (`pkg/api/http/cache.go:147`)
- Buckets / queues: none
- Idempotent: core GET paths are read-only. `/store` is content-addressed (SHA1), so a repeated write gives the same result.
  `/cache` PUT overwrites

## 5. Observability
- Health: `GET /healthz` (liveness), `GET /readyz` (readiness)
- Gap: both are in-memory flags. They go false only on shutdown, on `--unhealthy`/`--unready`,
  or after `POST /readyz/disable`. They check no dependency. For v1 (no deps) process-only readiness is acceptable
- Logs: stdout, structured JSON (zap)
- Metrics: Prometheus `/metrics` (port 9898 always, 9797 if enabled)
- Traced: OTel traces and logs export only when `--otel-service-name` is set
  (OTLP gRPC, endpoint from `OTEL_EXPORTER_OTLP_ENDPOINT`). Decide in P10

## 6. Config
All flags can also be set as `PODINFO_<FLAG>` env vars (`-` → `_`; `main.go:90-92`), or from `config.yaml` under `--config-path`.

| Key | plain/secret | Source | Reloads without restart? |
|---|---|---|---|
| `jwt-secret` / `PODINFO_JWT_SECRET` | **secret** | Secrets Manager → ESO (P5). The binary has a **hardcoded default** (`main.go:85`) that must never be used. **Do not inject as an env var:** `GET /env` returns `os.Environ()` (`pkg/api/http/env.go`) and would leak it. Lean: mount as `config.yaml` under `--config-path` (read at startup, `main.go:93-100`). Decision in P5 | **No.** It is read once at startup (`main.go:165`). Rotation needs a pod restart (e.g. a rollout triggered on secret change) |
| `cache-server` (only if Redis is used) | secret if it carries a password (`tcp://user:pass@host:port`) | ESO (P5) | No |
| `port`, `port-metrics`, `level`, `data-path`, `ui-*`, fault flags | plain | flags / `PODINFO_*` env via gitops values | No (read once at startup) |
| files under `--config-path` | plain or secret | ConfigMap / Secret volume | Watched (`pkg/fscache`), but only shown by `GET /configs`. The app uses none of these values |

## 7. Start/stop
- Cold start: sets ready right after the listeners start, with no warm-up
  (`server.go:244-249`). Expect about 1s; measure in P3
- Traps SIGTERM: yes (and SIGINT). Marks unhealthy and unready, sleeps 3s, then shuts down
  gRPC/HTTP/HTTPS with a 5s timeout (`--server-shutdown-timeout`). Total about 8s, under the default 30s grace period
- Gap: 3s may be too short for ALB target deregistration. **`--level=debug` skips the sleep** (`pkg/signals/shutdown.go`).
  Never run debug in prod
- Drain time target: revisit in P6/P9 (`preStop` sleep and/or pod readiness gates)

## 8. Dependencies
- Calls: none in the v1 config. Optional: Redis (`--cache-server`), backend podinfo via `POST /echo`
  (`--backend-url`, client timeout `--http-client-timeout` default **2m**), OTLP collector
- Called by: clients through the LB; kubelet probes; Prometheus scrape
- On dependency failure: **fail fast, no retry, no circuit breaker.** Redis not configured → `/cache` 400.
  Redis down → `/cache` 500, logged as a warning, and the pod stays Ready.
  `/echo` waits up to the 2m client timeout per backend

## 9. Ownership
- Dev on-call: you (learning project)
- Team channel: n/a
- Runbook: https://github.com/nazmur96/podinfo-platform/tree/main/docs (link the runbook when written, P10)
- Manifest owner: you. Update when ports, dependencies, secrets or shutdown behaviour change
