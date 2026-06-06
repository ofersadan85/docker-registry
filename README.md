# Internal Docker Registry

Simple internal container registry based on the official Docker Distribution image (`registry:3`).

References:

- <https://hub.docker.com/_/registry>
- <https://distribution.github.io/distribution/about/deploying/>

## Files

- `docker-compose.yml` - registry service definition.
- `images.txt` - upstream images to mirror (one per line).
- `sync-images.sh` - pulls, re-tags, and pushes images to internal registry (hostname and IP tags), with optional registry garbage collection.

## Start the registry

```bash
docker compose up -d
```

Optional custom port:

```bash
REGISTRY_PORT=5000 docker compose up -d
```

## Open ports

For this HTTP-only setup, open:

- `5000/tcp` from registry clients to the registry host (or your custom `REGISTRY_PORT` value).

## Configure Docker clients for HTTP registry

Because the registry is HTTP-only, Docker clients must treat it as insecure.

Example `/etc/docker/daemon.json`:

```json
{
  "insecure-registries": [
    "registry.internal.local:5000",
    "10.0.0.10:5000"
  ]
}
```

Restart Docker after updating daemon configuration.

## Mirror upstream images into the internal registry

1. Update `images.txt` with upstream image references, for example:
   - `nginx:latest`
   - `redis:7`
2. Run:

```bash
chmod +x sync-images.sh
./sync-images.sh \
  --registry-host registry.internal.local \
  --registry-ip 10.0.0.10 \
  --port 5000
```

The script will, for each source image:

1. pull the upstream image.
2. tag and push to `<hostname>:<port>/<image>`.
3. tag and push to `<ip>:<port>/<image>`.

It also supports environment variables:

```bash
REGISTRY_HOSTNAME=registry.internal.local \
REGISTRY_IP=10.0.0.10 \
REGISTRY_PORT=5000 \
IMAGES_FILE=images.txt \
./sync-images.sh
```

## Optional garbage collection

The script can also run Distribution garbage collection after syncing images:

```bash
./sync-images.sh \
  --registry-host registry.internal.local \
  --registry-ip 10.0.0.10 \
  --garbage-collect
```

Useful options:

- `--gc-dry-run` to show what would be deleted without deleting.
- `--gc-delete-untagged` to delete untagged manifests.
- `--registry-container internal-registry` to target a different registry container name.

The script stops the registry container before garbage collection and starts it again afterward, following Distribution guidance to avoid concurrent writes during GC.

## Pull mirrored images

Hostname:

```bash
docker pull registry.internal.local:5000/nginx:latest
```

IP:

```bash
docker pull 10.0.0.10:5000/nginx:latest
```
