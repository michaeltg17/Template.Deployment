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

# Docker on Windows (Docker Desktop) needs Windows-style paths for the HOST side
# of a bind mount (-v <host>:<container>) and for the build context. Git Bash
# reports Unix-style paths (/e/1/..., /c/Users/...), which docker rejects, and
# its MSYS layer also rewrites bare container paths like -w /app into
# C:\Program Files\Git\app. To handle both:
#   - host_path converts a Unix host path to a Windows path on Windows
#     (E:\1\..., C:\Users\...); on Linux/macOS it passes the path through.
#   - MSYS_NO_PATHCONV=1 stops MSYS from rewriting the container-side paths
#     (/app, /root/.aws, -w /app) and the command string when calling docker.
is_windows() { case "$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')" in msys*|cygwin*|mingw*|windows*) return 0 ;; *) return 1 ;; esac; }
host_path() { if is_windows && command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
if is_windows; then export MSYS_NO_PATHCONV=1; fi

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
  docker build -q -t "$IMAGE" -f "$(host_path "$SCRIPT_DIR")/Dockerfile.tools" "$(host_path "$REPO_ROOT")"
fi

# Mount host credential dirs if they exist (read-write: kubectl/helm write
# kubeconfig context files, aws may cache). The host side is converted to a
# Windows path on Windows (see host_path); the container side is /root/<basename>
# because the container's HOME is /root (so the tools find ~/.aws, ~/.kube, ...).
MOUNTS=()
for d in "$HOME/.aws" "$HOME/.kube" "$HOME/.config"; do
  if [ -d "$d" ]; then
    MOUNTS+=(-v "$(host_path "$d"):/root/$(basename "$d")")
  fi
done

# Run the captured args as the container command (e.g. `-c "bash common/ci.sh"`
# becomes `bash -c "bash common/ci.sh"`). With no args, drop into an interactive
# shell. -it only when attached to a TTY (so `... | tools-docker.sh` still works).
if [ -t 0 ] && [ -t 1 ]; then
  if [ "${#ARGS[@]}" -eq 0 ]; then
    exec docker run -it --rm "${MOUNTS[@]}" -v "$(host_path "$REPO_ROOT"):/app" -w /app "$IMAGE" bash
  fi
  exec docker run -it --rm "${MOUNTS[@]}" -v "$(host_path "$REPO_ROOT"):/app" -w /app "$IMAGE" bash "${ARGS[@]}"
fi

if [ "${#ARGS[@]}" -eq 0 ]; then
  exec docker run --rm "${MOUNTS[@]}" -v "$(host_path "$REPO_ROOT"):/app" -w /app "$IMAGE" bash
fi

exec docker run --rm "${MOUNTS[@]}" -v "$(host_path "$REPO_ROOT"):/app" -w /app "$IMAGE" bash "${ARGS[@]}"
