# syntax=docker/dockerfile:1
#
# Build context: the /server directory (see compose.yaml).
#   docker build -f docker/Dockerfile --build-arg VERSION=0.1.0 server

FROM golang:1.25 AS build
WORKDIR /src

# Dependencies first, so they are cached until go.mod or go.sum change.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath \
    -ldflags "-s -w -X main.version=${VERSION}" \
    -o /out/server ./cmd/server

# Empty mount points owned by the runtime user, so named volumes inherit write
# access. Bind mounts need scripts/init-volumes.sh instead.
RUN mkdir -p /out/data /out/certs

# Distroless static: no shell, no package manager, runs as UID 65532.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/server /server
COPY --from=build --chown=65532:65532 /out/data /data
COPY --from=build --chown=65532:65532 /out/certs /certs

USER 65532:65532
EXPOSE 8443
ENTRYPOINT ["/server"]
