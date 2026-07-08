ARG KOMO_VERS=latest

FROM golang:alpine AS jsonnet-builder
RUN go install github.com/google/go-jsonnet/cmd/jsonnet@latest

FROM ghcr.io/moghtech/komodo-periphery:${KOMO_VERS}
COPY --from=jsonnet-builder /go/bin/jsonnet /usr/local/bin/jsonnet
