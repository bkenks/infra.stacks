# 01-02-01 Fleet logs go to VictoriaLogs, collected by Vector off the docker socket

## Decision

`platform/monitoring/victorialogs` runs one VictoriaLogs on `biggy`, published on
`19428` without a `host_ip` so the rest of the fleet can reach it over the `.internal`
zone. `platform/monitoring/log-agent` runs one Vector per host; it tails the docker
socket and ships every container's stdout/stderr to that instance.

Retention is 90 days (`-retentionPeriod=90d`). The sink endpoint is
`registry.endpoint.serviceGroup.victorialogs`, so moving the store to another host is one
line in the registry.

Both services carry `komodo.skip`, so `StopAllContainers` leaves the pipeline running.

## Why

Komodo reads logs live off the daemon. When a container crash-loops, Komodo recreates it
and the previous container — along with its `json-file` log — is gone, which is exactly
the window worth reading.

VictoriaLogs over Loki: a single Go binary with no object storage, no index tuning and no
chunk lifecycle to operate. It has its own query UI, so nothing else has to be stood up to
read a log.

**Vector over the `loki`/`fluentd` docker log drivers.** A log driver writes from inside
the container's own lifecycle: in blocking mode it stalls the container when the sink is
down, and in non-blocking mode it drops silently. Vector reads the socket from outside, so
a container's fate and its logs' fate are separate, and Vector's own disk buffer (256 MiB,
`when_full: block`) covers a VictoriaLogs outage.

**Vector over vlagent**, the first-party agent: vlagent collects from Kubernetes pods and
from file globs. Pointing it at `/var/lib/docker/containers/*/*-json.log` would yield log
lines keyed by container id and nothing else. Vector's `docker_logs` source attaches
`container_name`, `image`, `stream` and container labels, which is what makes a crash loop
searchable after the fact.

`host` is overwritten in a `remap` transform from the `HOST` deploy variable, because
`docker_logs` fills it from the container's own hostname — the same string on every host.
`host,container_name` are the log stream fields, so one container's history is one stream
across restarts.
