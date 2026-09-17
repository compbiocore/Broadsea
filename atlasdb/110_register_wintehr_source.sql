\set ON_ERROR_STOP on

-- Run explicitly after the WintEHR CDM and Achilles results schemas exist.
-- Required psql variables: source_connection, cdm_schema, vocab_schema,
-- results_schema. This migration preserves every other Atlas source.
INSERT INTO webapi.source (
    source_id, source_name, source_key, source_connection, source_dialect
)
SELECT COALESCE(MAX(source_id), 0) + 1,
       'WintEHR Synthetic FHIR OMOP',
       'WINTEHR',
       :'source_connection',
       'postgresql'
FROM webapi.source
WHERE NOT EXISTS (SELECT 1 FROM webapi.source WHERE source_key = 'WINTEHR');

UPDATE webapi.source
SET source_name = 'WintEHR Synthetic FHIR OMOP',
    source_connection = :'source_connection',
    source_dialect = 'postgresql'
WHERE source_key = 'WINTEHR';

SELECT source_id AS wintehr_source_id
FROM webapi.source
WHERE source_key = 'WINTEHR'
\gset

DELETE FROM webapi.source_daimon WHERE source_id = :wintehr_source_id;

INSERT INTO webapi.source_daimon (
    source_daimon_id, source_id, daimon_type, table_qualifier, priority
)
SELECT COALESCE(MAX(source_daimon_id), 0) + 1,
       :wintehr_source_id, 0, :'cdm_schema', 0
FROM webapi.source_daimon;

INSERT INTO webapi.source_daimon (
    source_daimon_id, source_id, daimon_type, table_qualifier, priority
)
SELECT COALESCE(MAX(source_daimon_id), 0) + 1,
       :wintehr_source_id, 1, :'vocab_schema', 20
FROM webapi.source_daimon;

INSERT INTO webapi.source_daimon (
    source_daimon_id, source_id, daimon_type, table_qualifier, priority
)
SELECT COALESCE(MAX(source_daimon_id), 0) + 1,
       :wintehr_source_id, 2, :'results_schema', 0
FROM webapi.source_daimon;
