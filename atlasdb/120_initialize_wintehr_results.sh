#!/bin/bash
# Build the WebAPI results-schema support objects required by Atlas reports.
set -euo pipefail

BROADSEA_DIR=${BROADSEA_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
WEBAPI_DDL_URL=${WEBAPI_DDL_URL:-http://127.0.0.1/WebAPI/ddl/results}
RESULTS_SCHEMA=${RESULTS_DATABASE_SCHEMA:-wintehr_results}
VOCAB_SCHEMA=${VOCAB_DATABASE_SCHEMA:-omop_vocab}
TEMP_SCHEMA=${SCRATCH_DATABASE_SCHEMA:-wintehr_scratch}
ddl_file=$(mktemp)
trap 'rm -f "$ddl_file"' EXIT

echo "Initializing Atlas support tables in $RESULTS_SCHEMA"
curl --fail --silent --show-error --get "$WEBAPI_DDL_URL" \
  --data-urlencode dialect=postgresql \
  --data-urlencode "schema=$RESULTS_SCHEMA" \
  --data-urlencode "vocabSchema=$VOCAB_SCHEMA" \
  --data-urlencode "tempSchema=$TEMP_SCHEMA" \
  --data-urlencode initConceptHierarchy=true \
  --output "$ddl_file"

# Do not send an HTML error page or incomplete response into PostgreSQL.
grep -Eqi 'concept_hierarchy' "$ddl_file" || {
  echo "WebAPI DDL response did not contain concept_hierarchy; refusing to execute it." >&2
  head -20 "$ddl_file" >&2
  exit 1
}

cd "$BROADSEA_DIR"
docker compose exec -T broadsea-atlasdb \
  psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 < "$ddl_file"

hierarchy_count=$(docker compose exec -T broadsea-atlasdb \
  psql -X -U postgres -d postgres -tAc \
  "select count(*) from ${RESULTS_SCHEMA}.concept_hierarchy")
hierarchy_count=${hierarchy_count//[[:space:]]/}
[[ $hierarchy_count =~ ^[0-9]+$ && $hierarchy_count -gt 0 ]] || {
  echo "Atlas concept_hierarchy was created but is empty." >&2
  exit 1
}
echo "Atlas results schema ready: $hierarchy_count concept hierarchy rows"
