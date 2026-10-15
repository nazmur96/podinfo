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
mise exec -- pre-commit install --hook-types pre-commit --hook-types commit-msg
```

| Hook | What it stops |
|---|---|
| **gitleaks** | Secrets in the commit |
| **no-commit-to-branch** | Accidental commits on `master` (local only) |
| **conventional-pre-commit** | Non-Conventional Commit messages |
| **hadolint** | Dockerfile issues (when a Dockerfile is in the commit) |

`git commit --no-verify` skips hooks. **CI re-runs the same class of checks in
P7**, so skipping locally is not a bypass of the pipeline.
