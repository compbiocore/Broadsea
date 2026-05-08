#!/usr/bin/env bash
set -euo pipefail

# Broadsea shutdown script
# Usage examples:
#   ./shutdown.sh
#   ./shutdown.sh --clean-ares
#   ./shutdown.sh --volumes    # destructive: deletes Docker volumes too

cd "$(dirname "$0")"

CLEAN_ARES="false"
DELETE_VOLUMES="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean-ares)
      CLEAN_ARES="true"
      shift
      ;;
    --volumes)
      DELETE_VOLUMES="true"
      shift
      ;;
    -h|--help)
      cat <<HELP
Usage: ./shutdown.sh [options]

Options:
  --clean-ares      Delete ./ares/data/* after shutdown.
  --volumes         Also delete Docker volumes. Destructive: removes database/post-processing volumes.
HELP
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f docker-compose.yml ]]; then
  echo "Could not find docker-compose.yml. Put this script in the Broadsea root folder." >&2
  exit 1
fi

DOWN_ARGS=(--profile default --profile ares --profile cdm-postprocessing --profile achilles --profile dqd --profile aresindexer down --remove-orphans)

if [[ "$DELETE_VOLUMES" == "true" ]]; then
  echo "Stopping Broadsea and deleting Docker volumes..."
  DOWN_ARGS+=(--volumes)
else
  echo "Stopping Broadsea while keeping Docker volumes..."
fi

docker compose "${DOWN_ARGS[@]}"

echo "Removing any leftover one-shot post-processing containers..."
docker rm -f broadsea-run-achilles broadsea-run-dqd broadsea-run-aresindexer 2>/dev/null || true

if [[ "$CLEAN_ARES" == "true" ]]; then
  echo "Cleaning ./ares/data..."
  mkdir -p ./ares/data
  rm -rf ./ares/data/*
fi

echo
echo "Remaining Broadsea containers, if any:"
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | grep -E 'broadsea|ohdsi|atlas|webapi|traefik' || true

echo
echo "Shutdown complete."
