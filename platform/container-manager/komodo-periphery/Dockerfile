ARG KOMO_VERS=latest

# Build jsonnet binary from source (handles any arch via buildx)
FROM golang:alpine AS jsonnet-builder
RUN go install github.com/google/go-jsonnet/cmd/jsonnet@latest

# Extend periphery with jsonnet
FROM ghcr.io/moghtech/komodo-periphery:${KOMO_VERS}
COPY --from=jsonnet-builder /go/bin/jsonnet /usr/local/bin/jsonnet
