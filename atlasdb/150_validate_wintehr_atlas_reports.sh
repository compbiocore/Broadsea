#!/bin/bash
# Verify the exact WebAPI payloads rendered by Atlas Data Sources.
set -euo pipefail

webapi_ip=$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ohdsi-webapi)
[[ -n $webapi_ip ]] || {
  echo "Could not determine the ohdsi-webapi container address." >&2
  exit 1
}

person_json=$(mktemp)
condition_era_json=$(mktemp)
trap 'rm -f "$person_json" "$condition_era_json"' EXIT

person_url="http://${webapi_ip}:8080/WebAPI/cdmresults/WINTEHR/person"
condition_era_url="http://${webapi_ip}:8080/WebAPI/cdmresults/WINTEHR/conditionera"

for _ in {1..30}; do
  if curl --fail --silent --show-error --max-time 30 "$person_url" --output "$person_json"; then
    break
  fi
  sleep 2
done

[[ -s $person_json ]] || {
  echo "WebAPI did not return the WintEHR person report." >&2
  exit 1
}

curl --fail --silent --show-error --max-time 30 \
  "$condition_era_url" --output "$condition_era_json"

python3 "$(dirname "$0")/150_validate_wintehr_atlas_reports.py" \
  "$person_json" "$condition_era_json"
