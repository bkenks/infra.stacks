# "infistodokr" Image

## Model

### Per-Service Labels

**Minimum Required:**
infistodokr.project="project-name"
infistodokr.secret_path="/folder/in/infisical"
infistodokr.

**repo_root/templates/init-secrets/compose.yaml:**

```yaml
name: alpine

services:
  init:
    image: alpine:3.24.1
    user: root
    volumes:
      - "./secret-templates:/in:ro"
      - "/srv/docker/secret-templates:/out"
    entrypoint:
    - /bin/sh
    - ./entrypoint.sh
```

**repo_root/templates/init-secrets/entrypoint.sh:**

```bash
cp -a /in/. /out/
```

**repo_root/templates/consumer/compose.yaml:**

```yaml

```
