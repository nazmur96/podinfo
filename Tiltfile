# P3-9 inner loop (ADR-0012): save a Go file → new image → loaded into kind →
# rolled out behind the Gateway. Same image (Dockerfile), same manifests
# (k8s/overlays/dev) and same Secret as scripts/deploy.sh: Tilt only automates
# the loop, it doesn't define a second way to run podinfo.
# Needs: scripts/cluster-up.sh, scripts/install-local-platform.sh,
# scripts/make-local-secret.sh. Run: mise exec -- tilt up
# The CUJ still runs against it: BASE=https://podinfo.localhost scripts/cuj.sh

allow_k8s_contexts('kind-podinfo')
# Tilt prunes the host's Docker build cache by default (first run here:
# 80 caches, 660 MB), including other projects' caches. Never.
docker_prune_settings(disable=True)

# Only the files that go into the image trigger a rebuild.
docker_build(
    'podinfo',
    '.',
    build_args={'REVISION': str(local('git rev-parse HEAD', quiet=True)).strip()},
    only=['go.mod', 'go.sum', 'cmd', 'pkg', 'ui'],
    ignore=['**/*_test.go'],
)

# The Secret from the git-ignored .secrets/ (D5), labelled like deploy.sh's.
watch_file('.secrets/config.yaml')
k8s_yaml(local(
    'kubectl -n podinfo-dev create secret generic podinfo-config' +
    ' --from-file=config.yaml=.secrets/config.yaml --dry-run=client -o yaml' +
    ' | kubectl label --local -f - -o yaml' +
    ' app.kubernetes.io/name=podinfo app.kubernetes.io/instance=podinfo-dev' +
    ' app.kubernetes.io/component=api app.kubernetes.io/part-of=podinfo' +
    ' app.kubernetes.io/managed-by=kubectl team=nazmur96',
    quiet=True,
))
k8s_yaml(kustomize('k8s/overlays/dev'))

k8s_resource('podinfo', objects=['podinfo-config:secret'])
