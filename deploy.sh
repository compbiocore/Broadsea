#!/usr/bin/env bash
set -euo pipefail

# Broadsea local deploy / smoke-test script
# Run from anywhere. The script moves to the directory where it is located.
# Usage examples:
#   ./deploy.sh
#   ./deploy.sh --clean-ares
#   ./deploy.sh --full-ares --clean-ares
#   TAG=2026-05-06-fix2 ./deploy.sh --clean-ares

cd "$(dirname "$0")"

TAG="${TAG:-2026-05-06-fix2}"
GHCR_ORG="${GHCR_ORG:-compbiocore}"
PLATFORM="${PLATFORM:-linux/amd64}"
CLEAN_ARES="false"
FULL_ARES="false"
SKIP_PULL="false"
SKIP_POSTPROCESSING="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean-ares)
      CLEAN_ARES="true"
      shift
      ;;
    --full-ares)
      FULL_ARES="true"
      shift
      ;;
    --skip-pull)
      SKIP_PULL="true"
      shift
      ;;
    --skip-postprocessing)
      SKIP_POSTPROCESSING="true"
      shift
      ;;
    -h|--help)
      cat <<HELP
Usage: ./deploy.sh [options]

Options:
  --clean-ares            Delete ./ares/data/* before running, so generated files are clearly fresh.
  --full-ares             Set ARES_RUN_NETWORK=TRUE for this run by creating .env.local.generated.
  --skip-pull             Do not explicitly docker pull the GHCR post-processing images first.
  --skip-postprocessing   Start Broadsea core services only. Do not run Achilles/DQD/AresIndexer.

Environment variables:
  TAG                     Image tag. Default: 2026-05-06-fix2
  GHCR_ORG                GHCR org/user. Default: compbiocore
  PLATFORM                Docker platform. Default: linux/amd64
HELP
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need_cmd docker

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose v2 is required. Try: docker compose version" >&2
  exit 1
fi

if [[ ! -f docker-compose.yml ]]; then
  echo "Could not find docker-compose.yml. Put this script in the Broadsea root folder." >&2
  exit 1
fi

if [[ "$FULL_ARES" == "true" ]]; then
  # Docker Compose only auto-loads .env, so this creates a temporary env file and uses --env-file.
  # It removes duplicate ARES_RUN_NETWORK lines and forces TRUE for this test run.
  awk '!/^ARES_RUN_NETWORK=/' .env > .env.local.generated
  echo 'ARES_RUN_NETWORK="TRUE"' >> .env.local.generated
  ENV_FILE_ARGS=(--env-file .env.local.generated)
  echo "Using ARES_RUN_NETWORK=TRUE for this run."
else
  ENV_FILE_ARGS=()
fi

if [[ "$CLEAN_ARES" == "true" ]]; then
  echo "Cleaning ./ares/data so Ares output can be validated as newly generated..."
  mkdir -p ./ares/data
  rm -rf ./ares/data/*
fi

if [[ "$SKIP_PULL" != "true" ]]; then
  echo "Pulling GHCR post-processing images for ${PLATFORM}..."
  docker pull --platform "${PLATFORM}" "ghcr.io/${GHCR_ORG}/broadsea-achilles:${TAG}"
  docker pull --platform "${PLATFORM}" "ghcr.io/${GHCR_ORG}/broadsea-dqd:${TAG}"
  docker pull --platform "${PLATFORM}" "ghcr.io/${GHCR_ORG}/broadsea-aresindexer:${TAG}"
fi

echo "Starting Broadsea core services..."
docker compose "${ENV_FILE_ARGS[@]}" --profile default --profile ares up -d

echo
echo "Current container status:"
docker compose "${ENV_FILE_ARGS[@]}" ps

echo
echo "Checking local endpoints..."
for url in \
  "http://127.0.0.1/" \
  "http://127.0.0.1/atlas" \
  "http://127.0.0.1/WebAPI/info" \
  "http://127.0.0.1/ares"; do
  echo "---- ${url}"
  curl -fsSI "$url" | head -n 1 || true
done

if [[ "$SKIP_POSTPROCESSING" == "true" ]]; then
  echo
echo "Skipped CDM post-processing. Core Broadsea services are up."
  exit 0
fi

echo
echo "Running CDM post-processing: Achilles -> DQD -> AresIndexer..."
docker compose "${ENV_FILE_ARGS[@]}" --profile cdm-postprocessing up \
  --abort-on-container-exit \
  --exit-code-from broadsea-run-aresindexer-after \
  broadsea-run-aresindexer-after

echo
echo "Checking generated Ares files on host..."
mkdir -p ./ares/data
ls -lh ./ares/data || true
find ./ares/data -maxdepth 2 -type f | sort | head -50 || true

echo
echo "Checking Ares JSON endpoints..."
for url in \
  "http://127.0.0.1/ares/data/index.json" \
  "http://127.0.0.1/ares/data/export_query_index.json"; do
  echo "---- ${url}"
  curl -fsSI "$url" | head -n 1 || true
done

echo
echo "Checking database-side post-processing outputs..."
docker exec broadsea-atlasdb psql -U postgres -d postgres -c "
select table_schema, table_name
from information_schema.tables
where table_schema = 'demo_cdm_results'
  and (table_name ilike 'achilles%' or table_name ilike '%dq%')
order by table_name
limit 40;
" || true

echo
echo "Done. Review the output above for HTTP 200 responses and generated files in ./ares/data."
