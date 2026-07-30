#!/bin/bash
# Validate and transactionally load an OSCAR-produced OMOP artifact.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/wintehr-omop.tar.gz" >&2
  exit 2
fi

ARTIFACT=$(realpath "$1")
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IMAGE=${FHIR_TO_OMOP_IMAGE:-ghcr.io/compbiocore/fhir-to-omop:latest}
NETWORK=${BROADSEA_DOCKER_NETWORK:-broadsea_default}
CONFIG=${FHIR_TO_OMOP_CONFIG:-$SCRIPT_DIR/config/wintehr-artifact.yaml}
ENV_FILE=${FHIR_TO_OMOP_ENV_FILE:-$SCRIPT_DIR/.env.wintehr-loader}

[[ -f "$ARTIFACT" ]] || { echo "Artifact does not exist: $ARTIFACT" >&2; exit 2; }
[[ -f "$CONFIG" ]] || { echo "Loader config does not exist: $CONFIG" >&2; exit 2; }
[[ -f "$ENV_FILE" ]] || { echo "Loader environment file does not exist: $ENV_FILE" >&2; exit 2; }

docker run --rm \
  --network "$NETWORK" \
  --env-file "$ENV_FILE" \
  -v "$ARTIFACT:/input/artifact.tar.gz:ro" \
  -v "$CONFIG:/app/config/artifact-loader.yaml:ro" \
  "$IMAGE" \
  artifact-check --artifact /input/artifact.tar.gz

docker run --rm \
  --network "$NETWORK" \
  --env-file "$ENV_FILE" \
  -v "$ARTIFACT:/input/artifact.tar.gz:ro" \
  -v "$CONFIG:/app/config/artifact-loader.yaml:ro" \
  "$IMAGE" \
  load-artifact --config /app/config/artifact-loader.yaml --artifact /input/artifact.tar.gz

echo "WintEHR OMOP artifact loaded. Run Achilles/DQD before registering or refreshing Atlas."
