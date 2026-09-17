#!/bin/bash
# Build the WebAPI results-schema support objects required by Atlas reports.
set -euo pipefail

BROADSEA_DIR=${BROADSEA_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
RESULTS_SCHEMA=${RESULTS_DATABASE_SCHEMA:-wintehr_results}
VOCAB_SCHEMA=${VOCAB_DATABASE_SCHEMA:-omop_vocab}
TEMP_SCHEMA=${SCRATCH_DATABASE_SCHEMA:-wintehr_scratch}
ddl_file=$(mktemp)
idempotent_ddl_file=$(mktemp)
trap 'rm -f "$ddl_file" "$idempotent_ddl_file"' EXIT

echo "Initializing Atlas support tables in $RESULTS_SCHEMA"
if [[ -z ${WEBAPI_DDL_URL:-} ]]; then
  webapi_ip=$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ohdsi-webapi)
  [[ -n $webapi_ip ]] || {
    echo "Could not determine the ohdsi-webapi container address." >&2
    exit 1
  }
  WEBAPI_DDL_URL="http://${webapi_ip}:8080/WebAPI/ddl/results"
fi

http_code=$(curl --silent --show-error --get "$WEBAPI_DDL_URL" \
  --connect-timeout 10 \
  --max-time 300 \
  --data-urlencode dialect=postgresql \
  --data-urlencode "schema=$RESULTS_SCHEMA" \
  --data-urlencode "vocabSchema=$VOCAB_SCHEMA" \
  --data-urlencode "tempSchema=$TEMP_SCHEMA" \
  --data-urlencode initConceptHierarchy=true \
  --output "$ddl_file" \
  --write-out '%{http_code}')
[[ $http_code == 200 ]] || {
  echo "WebAPI returned HTTP $http_code instead of results-schema SQL." >&2
  head -20 "$ddl_file" >&2
  exit 1
}

# Do not send an HTML error page or incomplete response into PostgreSQL.
grep -Eqi 'concept_hierarchy' "$ddl_file" || {
  echo "WebAPI DDL response did not contain concept_hierarchy; refusing to execute it." >&2
  head -20 "$ddl_file" >&2
  exit 1
}

# WebAPI's generated results DDL is not fully rerunnable: some index
# statements omit IF NOT EXISTS even though the surrounding tables are
# intentionally retained. Make index creation idempotent before applying it.
sed -E \
  -e 's/^CREATE UNIQUE INDEX /CREATE UNIQUE INDEX IF NOT EXISTS /' \
  -e 's/^CREATE INDEX /CREATE INDEX IF NOT EXISTS /' \
  "$ddl_file" > "$idempotent_ddl_file"

cd "$BROADSEA_DIR"
docker compose exec -T broadsea-atlasdb \
  psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 < "$idempotent_ddl_file"

# WebAPI's generated hierarchy may omit concepts used by the person and
# condition/condition-era Achilles reports. Backfill those used report strata
# from the loaded OMOP vocabulary so Atlas can resolve their labels.
docker compose exec -T broadsea-atlasdb \
  psql -X -U postgres -d postgres \
  -v ON_ERROR_STOP=1 \
  -v results_schema="$RESULTS_SCHEMA" \
  -v vocab_schema="$VOCAB_SCHEMA" \
  < "$BROADSEA_DIR/atlasdb/130_backfill_wintehr_concept_hierarchy.sql"

# WebAPI's vocabulary endpoints use the highest-priority vocabulary daimon.
# Keep WINTEHR as the default so Atlas can resolve WintEHR concept labels.
docker compose exec -T broadsea-atlasdb \
  psql -X -U postgres -d postgres \
  -v ON_ERROR_STOP=1 \
  < "$BROADSEA_DIR/atlasdb/140_make_wintehr_vocabulary_default.sql"

hierarchy_count=$(docker compose exec -T broadsea-atlasdb \
  psql -X -U postgres -d postgres -tAc \
  "select count(*) from ${RESULTS_SCHEMA}.concept_hierarchy")
hierarchy_count=${hierarchy_count//[[:space:]]/}
[[ $hierarchy_count =~ ^[0-9]+$ && $hierarchy_count -gt 0 ]] || {
  echo "Atlas concept_hierarchy was created but is empty." >&2
  exit 1
}
echo "Atlas results schema ready: $hierarchy_count concept hierarchy rows"
