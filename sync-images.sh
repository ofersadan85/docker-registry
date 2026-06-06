#!/usr/bin/env bash
set -euo pipefail

IMAGES_FILE="${IMAGES_FILE:-images.txt}"
REGISTRY_HOSTNAME="${REGISTRY_HOSTNAME:-}"
REGISTRY_IP="${REGISTRY_IP:-}"
REGISTRY_PORT="${REGISTRY_PORT:-5000}"
REGISTRY_CONTAINER="${REGISTRY_CONTAINER:-internal-registry}"
RUN_GARBAGE_COLLECTION=false
GC_DRY_RUN=false
GC_DELETE_UNTAGGED=false

usage() {
  cat <<'EOF'
Usage:
  sync-images.sh [--images-file PATH] --registry-host HOSTNAME --registry-ip IP [--port PORT] [--garbage-collect] [--gc-dry-run] [--gc-delete-untagged] [--registry-container NAME]

Environment variables (optional alternatives):
  IMAGES_FILE, REGISTRY_HOSTNAME, REGISTRY_IP, REGISTRY_PORT, REGISTRY_CONTAINER
EOF
}

run_garbage_collection() {
  local gc_args=(garbage-collect)
  local was_running
  local registry_stopped=false

  if [[ "$GC_DRY_RUN" == "true" ]]; then
    gc_args+=(--dry-run)
  fi

  if [[ "$GC_DELETE_UNTAGGED" == "true" ]]; then
    gc_args+=(--delete-untagged)
  fi

  gc_args+=(/etc/distribution/config.yml)

  if ! docker container inspect "$REGISTRY_CONTAINER" >/dev/null 2>&1; then
    echo "Registry container not found: $REGISTRY_CONTAINER" >&2
    exit 1
  fi

  was_running="$(docker inspect -f '{{.State.Running}}' "$REGISTRY_CONTAINER")"
  if [[ "$was_running" == "true" ]]; then
    echo "Stopping ${REGISTRY_CONTAINER} before garbage collection"
    docker stop "$REGISTRY_CONTAINER" >/dev/null
    registry_stopped=true
  fi

  restart_registry_if_needed() {
    if [[ "$registry_stopped" == "true" ]]; then
      echo "Starting ${REGISTRY_CONTAINER} after garbage collection"
      docker start "$REGISTRY_CONTAINER" >/dev/null
    fi
  }

  trap restart_registry_if_needed EXIT

  echo "Running registry garbage collection"
  docker run --rm --volumes-from "$REGISTRY_CONTAINER" registry:3 registry "${gc_args[@]}"

  restart_registry_if_needed
  trap - EXIT
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --images-file)
      IMAGES_FILE="$2"
      shift 2
      ;;
    --registry-host|--registry-hostname)
      REGISTRY_HOSTNAME="$2"
      shift 2
      ;;
    --registry-ip)
      REGISTRY_IP="$2"
      shift 2
      ;;
    --port)
      REGISTRY_PORT="$2"
      shift 2
      ;;
    --registry-container)
      REGISTRY_CONTAINER="$2"
      shift 2
      ;;
    --garbage-collect)
      RUN_GARBAGE_COLLECTION=true
      shift
      ;;
    --gc-dry-run)
      RUN_GARBAGE_COLLECTION=true
      GC_DRY_RUN=true
      shift
      ;;
    --gc-delete-untagged)
      RUN_GARBAGE_COLLECTION=true
      GC_DELETE_UNTAGGED=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required but not installed or not in PATH." >&2
  exit 1
fi

if [[ -z "$REGISTRY_HOSTNAME" ]]; then
  echo "Missing registry hostname. Use --registry-host or REGISTRY_HOSTNAME." >&2
  exit 1
fi

if [[ -z "$REGISTRY_IP" ]]; then
  echo "Missing registry IP. Use --registry-ip or REGISTRY_IP." >&2
  exit 1
fi

if [[ ! -f "$IMAGES_FILE" ]]; then
  echo "Images file not found: $IMAGES_FILE" >&2
  exit 1
fi

HOST_PREFIX="${REGISTRY_HOSTNAME}:${REGISTRY_PORT}"
IP_PREFIX="${REGISTRY_IP}:${REGISTRY_PORT}"

while IFS= read -r image || [[ -n "$image" ]]; do
  image="${image#"${image%%[![:space:]]*}"}"
  image="${image%"${image##*[![:space:]]}"}"

  if [[ -z "$image" || "${image:0:1}" == "#" ]]; then
    continue
  fi

  host_target="${HOST_PREFIX}/${image}"
  ip_target="${IP_PREFIX}/${image}"

  echo "Syncing ${image}"
  docker pull "$image"

  echo "Tagging -> ${host_target}"
  docker tag "$image" "$host_target"
  echo "Pushing -> ${host_target}"
  docker push "$host_target"

  echo "Tagging -> ${ip_target}"
  docker tag "$image" "$ip_target"
  echo "Pushing -> ${ip_target}"
  docker push "$ip_target"
done < "$IMAGES_FILE"

if [[ "$RUN_GARBAGE_COLLECTION" == "true" ]]; then
  run_garbage_collection
fi
