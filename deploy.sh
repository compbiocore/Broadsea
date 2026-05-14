#!/usr/bin/env bash
set -euo pipefail

# Broadsea local deploy / smoke-test script
# Run from the Broadsea root or from anywhere. The script moves to its own directory.
#
# Usage:
#   ./deploy.sh
#   ./deploy.sh --clean-ares
#   ./deploy.sh --full-ares --clean-ares
#   ./deploy.sh --skip-postprocessing
#   TAG=2026-05-06-fix2 ./deploy.sh
#
# This script:
#   1. Pulls GHCR post-processing images for linux/amd64
#   2. Starts Broadsea core services
#   3. Waits for broadsea-atlasdb to become healthy
#   4. Gives WebAPI/ATLAS/Ares time to initialize
#   5. Checks local endpoints
#   6. Runs Achilles -> DQD -> AresIndexer
#   7. Checks generated Ares files and database output tables

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
  --clean-ares            Delete ./ares/data/* before running.
  --full-ares             Force ARES_RUN_NETWORK=TRUE for this run.
  --skip-pull             Skip explicit GHCR docker pulls.
  --skip-postprocessing   Start core Broadsea services only.
  -h, --help              Show this help text.

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
need_cmd curl
need_cmd awk
need_cmd find

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose v2 is required. Try: docker compose version" >&2
  exit 1
fi

if [[ ! -f docker-compose.yml ]]; then
  echo "Could not find docker-compose.yml. Put this script in the Broadsea root folder." >&2
  exit 1
fi

if [[ ! -f .env ]]; then
  echo "Warning: .env file not found. Docker Compose will run without the project .env file." >&2
fi

# Compose helper.
# This avoids empty Bash array expansion issues with set -u on macOS Bash.
dc() {
  if [[ "$FULL_ARES" == "true" ]]; then
    docker compose --env-file .env.local.generated "$@"
  else
    docker compose "$@"
  fi
}

if [[ "$FULL_ARES" == "true" ]]; then
  if [[ ! -f .env ]]; then
    echo "Cannot use --full-ares because .env was not found." >&2
    exit 1
  fi

  awk '!/^ARES_RUN_NETWORK=/' .env > .env.local.generated
  echo 'ARES_RUN_NETWORK=TRUE' >> .env.local.generated
  echo "Using ARES_RUN_NETWORK=TRUE for this run via .env.local.generated."
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

echo
echo "Removing old post-processing containers, if present..."
docker rm -f broadsea-run-achilles broadsea-run-dqd broadsea-run-aresindexer 2>/dev/null || true

echo
echo "Starting Broadsea core services..."
dc --profile default --profile ares up -d

echo
echo "Waiting for broadsea-atlasdb to become healthy..."

for i in {1..60}; do
  db_status="$(docker inspect --format='{{.State.Health.Status}}' broadsea-atlasdb 2>/dev/null || echo unknown)"

  if [[ "$db_status" == "healthy" ]]; then
    echo "broadsea-atlasdb is healthy."
    break
  fi

  echo "broadsea-atlasdb status: ${db_status}. Waiting 5 seconds..."
  sleep 5

  if [[ "$i" -eq 60 ]]; then
    echo "broadsea-atlasdb did not become healthy in time." >&2
    docker logs broadsea-atlasdb --tail 150 || true
    exit 1
  fi
done

echo
echo "Giving WebAPI, ATLAS, Traefik, and Ares extra time to initialize..."
sleep 30

echo
echo "Current container status:"
dc ps

echo
echo "Checking database schemas..."
docker exec broadsea-atlasdb psql -U postgres -d postgres -c "
select schema_name
from information_schema.schemata
where schema_name in ('demo_cdm', 'demo_cdm_results', 'webapi')
order by schema_name;
" || true

echo
echo "Checking local endpoints..."
for url in \
  "http://127.0.0.1/" \
  "http://127.0.0.1/atlas" \
  "http://127.0.0.1/WebAPI/info" \
  "http://127.0.0.1/ares"; do
  echo "---- ${url}"
  curl -sSI "$url" | head -n 1 || true
done

if [[ "$SKIP_POSTPROCESSING" == "true" ]]; then
  echo
  echo "Skipped CDM post-processing. Core Broadsea services are up."
  exit 0
fi

echo
echo "Running CDM post-processing: Achilles -> DQD -> AresIndexer..."

set +e
dc --profile cdm-postprocessing up \
  --abort-on-container-exit \
  --exit-code-from broadsea-run-aresindexer-after \
  broadsea-run-aresindexer-after

post_status=$?
set -e

echo
echo "Current container status after post-processing attempt:"
dc ps -a

echo
echo "---- broadsea-run-achilles logs"
docker logs broadsea-run-achilles 2>&1 | tail -150 || true

echo
echo "---- broadsea-run-dqd logs"
docker logs broadsea-run-dqd 2>&1 | tail -150 || true

echo
echo "---- broadsea-run-aresindexer logs"
docker logs broadsea-run-aresindexer 2>&1 | tail -150 || true

echo
echo "Trying to copy Achilles/DQD error reports, if present..."

docker cp broadsea-run-achilles:/postprocessing/achilles/data/demo_cdm/errorReportR.txt ./achilles_errorReportR.txt 2>/dev/null || true
docker cp broadsea-run-dqd:/postprocessing/dqd/data/demo_cdm/errorReportR.txt ./dqd_errorReportR.txt 2>/dev/null || true

if [[ -f ./achilles_errorReportR.txt ]]; then
  echo
  echo "---- ./achilles_errorReportR.txt"
  tail -150 ./achilles_errorReportR.txt || true
fi

if [[ -f ./dqd_errorReportR.txt ]]; then
  echo
  echo "---- ./dqd_errorReportR.txt"
  tail -150 ./dqd_errorReportR.txt || true
fi

echo
echo "Checking generated Ares files on host..."
mkdir -p ./ares/data
ls -lh ./ares/data || true
find ./ares/data -maxdepth 2 -type f | sort | head -50 || true

echo
echo "Checking expected Ares JSON files on host..."

if [[ -f ./ares/data/index.json ]]; then
  echo "Found ./ares/data/index.json"
  ls -lh ./ares/data/index.json
else
  echo "Missing ./ares/data/index.json"
fi

if [[ -f ./ares/data/export_query_index.json ]]; then
  echo "Found ./ares/data/export_query_index.json"
  ls -lh ./ares/data/export_query_index.json
else
  echo "Missing ./ares/data/export_query_index.json"
fi

echo
echo "Checking Ares files inside broadsea-ares container..."
docker exec broadsea-ares sh -lc '
  echo "Listing /usr/share/nginx/html/ares/data";
  ls -lh /usr/share/nginx/html/ares/data || true;
  echo;
  echo "Checking expected files inside container";
  ls -lh /usr/share/nginx/html/ares/data/index.json || true;
  ls -lh /usr/share/nginx/html/ares/data/export_query_index.json || true;
' || true

echo
echo "Checking Ares JSON endpoints..."
for url in \
  "http://127.0.0.1/ares/data/index.json" \
  "http://127.0.0.1/ares/data/export_query_index.json"; do
  echo "---- ${url}"
  curl -sSI "$url" | head -n 1 || true
done

echo
echo "Checking database-side post-processing outputs..."
docker exec broadsea-atlasdb psql -U postgres -d postgres -c "
select table_schema, table_name
from information_schema.tables
where table_schema = 'demo_cdm_results'
  and (
    table_name ilike 'achilles%'
    or table_name ilike '%dq%'
    or table_name ilike '%quality%'
  )
order by table_name
limit 40;
" || true

echo
echo "Done."

if [[ "$post_status" -ne 0 ]]; then
  echo
  echo "CDM post-processing failed with exit code ${post_status}."
  echo "The core stack may still be running. Review the logs and error reports printed above."
  exit "$post_status"
fi

echo
echo "Success criteria to confirm:"
echo "  1. GHCR image pulls succeeded"
echo "  2. broadsea-atlasdb became healthy"
echo "  3. Core Broadsea services are running"
echo "  4. Achilles, DQD, and AresIndexer completed"
echo "  5. ./ares/data contains generated files"
echo "  6. /ares/data/index.json returns HTTP 200"
echo "  7. /ares/data/export_query_index.json returns HTTP 200"