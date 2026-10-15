# syntax=docker/dockerfile:1.7
# Our image (P2-1): replaces upstream alpine+curl+netcat+podcli+named USER.
# Digests pinned; bump deliberately. Go < 30 MB budget (P2-5).

FROM golang:1.27-bookworm@sha256:5cf287a799e6b94384bad13d16b14904c531f51ba65792237e122ce42b392f61 AS build
WORKDIR /src

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY . .
ARG REVISION=unknown
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -trimpath \
      -ldflags="-s -w -X github.com/stefanprodan/podinfo/pkg/version.REVISION=${REVISION}" \
      -o /out/podinfo ./cmd/podinfo

FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab

ARG REVISION=unknown
ARG SOURCE=https://github.com/nazmur96/podinfo
ARG CREATED=unknown

LABEL org.opencontainers.image.source=$SOURCE \
      org.opencontainers.image.revision=$REVISION \
      org.opencontainers.image.created=$CREATED \
      org.opencontainers.image.title="podinfo" \
      org.opencontainers.image.description="podinfo learning fork: distroless, numeric UID, unsafe routes off by default"

WORKDIR /home/nonroot
COPY --from=build /out/podinfo /podinfo
COPY --chown=65532:65532 ./ui ./ui

# Distroless nonroot is UID/GID 65532 (numeric — required for runAsNonRoot).
USER 65532:65532
EXPOSE 9898
# Unsafe HTTP control routes stay off unless --enable-unsafe-endpoints (ADR-0006/0008).
ENTRYPOINT ["/podinfo"]
CMD ["--port=9898", "--ui-path=/home/nonroot/ui", "--data-path=/tmp/data"]
