# Contributing — nazmur96/podinfo

This is a fork of [stefanprodan/podinfo](https://github.com/stefanprodan/podinfo)
used as a learning project. Conventions (branches, commits, image tags) live
in the platform repo:
[conventions.md](https://github.com/nazmur96/podinfo-platform/blob/main/docs/conventions.md).
Ownership and release rules:
[ownership.md](https://github.com/nazmur96/podinfo-platform/blob/main/docs/ownership.md).

Default branch is `master`. Keep fork patches small and listed in
[MANIFEST.md](https://github.com/nazmur96/podinfo/blob/master/MANIFEST.md), so upstream syncs stay easy.

From P1-2: ticket branch → squash PR → delete branch (do not push straight to
`master`).

## Pre-commit hooks (P1-4)

```bash
mise trust && mise install
mise exec -- pre-commit install
```

| Hook | What it stops |
|---|---|
| **gitleaks** | Secrets in the commit |
| **no-commit-to-branch** | Accidental commits on `master` (local only) |
| **conventional-pre-commit** | Non-Conventional Commit messages |
| **hadolint** | Dockerfile issues (when a Dockerfile is in the commit) |

`git commit --no-verify` skips hooks. **CI re-runs the same class of checks in
P7**, so skipping locally is not a bypass of the pipeline.

## Working on podinfo against the local cluster (P3-9)

One-time: `mise trust && mise install`, then the cluster and its platform:

```bash
mise exec -- scripts/cluster-up.sh
mise exec -- scripts/install-local-platform.sh   # Gateway API, Envoy Gateway, cert-manager, local CA
mise exec -- scripts/make-local-secret.sh        # git-ignored JWT secret
```

| To … | Run | Notes |
|---|---|---|
| see a code change in the cluster | `mise exec -- tilt up` | Rebuilds the image on save and rolls it out behind the Gateway: **8-10 s** from save to served (measured). Same Dockerfile, overlay and Secret as `deploy.sh`. `tilt down` removes what it applied but keeps the namespace; run `scripts/deploy.sh` afterwards to get back to the scripted state |
| debug podinfo on your machine with cluster traffic | `mise exec -- scripts/mirrord.sh` | Builds podinfo and runs it locally as if it were one pod: that pod's env, its `/config` Secret and its share of Gateway traffic (`/version` shows commit `unknown` for those). Pass your own command to run something else (a debugger launch is untested here). Ctrl-C hands the traffic back |
| deploy the committed state | `mise exec -- scripts/deploy.sh` | Image tagged with the full git SHA |
| check it works | `CURL_CA_BUNDLE=$PWD/.certs/ca.crt BASE=https://podinfo.localhost EXPECT_SHA=$(git rev-parse HEAD) scripts/cuj.sh` | Plus `scripts/check-netpol.sh`, `scripts/check-labels.sh`, `scripts/rollout-drill.sh restart` |

mirrord limits: its agent is privileged, so it runs in its own `mirrord`
namespace (the one PSA exception, ADR-0012). podinfo's `/config` watcher
doesn't work under it, so a rotated Secret isn't picked up locally. The
build needs cgo (mirrord hooks a dynamically linked binary), which is why
mise pins `zig` as the C compiler.
