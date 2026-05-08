#!/usr/bin/env bash
set -euo pipefail

REGISTRY="ghcr.io/compbiocore"
TAG="${TAG:-2026-05-06}"
SECRET_FILE="./secrets/github_pat"

if [ ! -f "$SECRET_FILE" ]; then
  echo "ERROR: Missing $SECRET_FILE"
  echo "Create it with your GitHub PAT before building."
  exit 1
fi

echo "Building and pushing CDM post-processing images with tag: ${TAG}"

docker buildx build \
  --platform linux/amd64 \
  --secret id=GITHUB_PAT,src=${SECRET_FILE} \
  -t ${REGISTRY}/broadsea-achilles:${TAG} \
  ./achilles \
  --push

docker buildx build \
  --platform linux/amd64 \
  --secret id=GITHUB_PAT,src=${SECRET_FILE} \
  -t ${REGISTRY}/broadsea-dqd:${TAG} \
  ./dqd \
  --push

docker buildx build \
  --platform linux/amd64 \
  --secret id=GITHUB_PAT,src=${SECRET_FILE} \
  -t ${REGISTRY}/broadsea-aresindexer:${TAG} \
  ./ares \
  --push

echo "Done."