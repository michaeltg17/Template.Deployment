#!/usr/bin/env bash
# Run this repo's scripts inside the pinned tooling container (see
# Dockerfile.tools). Gives you the same Linux environment (terraform, kubectl,
# helm, aws, az, python3) on any host - no WSL, no per-tool installs.
#
# Usage:
#   bash common/tools-docker.sh                      # interactive shell
#   bash common/tools-docker.sh -c "<command>"       # run one command
#   bash common/tools-docker.sh --rebuild -c "..."   # force image rebuild
#
# Examples:
#   bash common/tools-docker.sh -c "bash aws/bootstrap/setup-eks.sh dev"
#   bash common/tools-docker.sh -c "bash common/k8s/deploy.sh dev aws"
#   bash common/tools-docker.sh -c "bash common/ci.sh"
#
# Credentials stay on the host: ~/.aws and ~/.kube are bind-mounted into the
# container (never baked into the image).

set -euo pipefail

IMAGE="template-deployment-tools:latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REBUILD=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --rebuild) REBUILD=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done

if [ "$REBUILD" -eq 1 ] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Building $IMAGE (first run or --rebuild)..."
  docker build -q -t "$IMAGE" -f "$SCRIPT_DIR/Dockerfile.tools" "$REPO_ROOT"
fi

# Mount host credential dirs if they exist (read-write: kubectl/helm write
# kubeconfig context files, aws may cache).
MOUNTS=()
for d in "$HOME/.aws" "$HOME/.kube" "$HOME/.config"; do
  if [ -d "$d" ]; then
    MOUNTS+=(-v "$d:/root/$d")
  fi
done

# -it only when attached to a TTY (so `... | tools-docker.sh` still works).
if [ -t 0 ] && [ -t 1 ]; then
  if [ "${#ARGS[@]}" -eq 0 ]; then
    exec docker run -it --rm "${MOUNTS[@]}" -v "$REPO_ROOT:/app" -w /app "$IMAGE" bash
  fi
  exec docker run -it --rm "${MOUNTS[@]}" -v "$REPO_ROOT:/app" -w /app "$IMAGE" bash -c "${ARGS[*]}"
fi

if [ "${#ARGS[@]}" -eq 0 ]; then
  exec docker run --rm "${MOUNTS[@]}" -v "$REPO_ROOT:/app" -w /app "$IMAGE" bash
fi

exec docker run --rm "${MOUNTS[@]}" -v "$REPO_ROOT:/app" -w /app "$IMAGE" bash -c "${ARGS[*]}"
