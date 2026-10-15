-- Cohort report generation looks up concept names through the CDM schema.
-- The FHIR loader keeps the Athena vocabulary in omop_vocab, while the CDM
-- DDL creates an empty wintehr_cdm.concept table. Expose that vocabulary to
-- cohort reports without duplicating millions of concept rows.
BEGIN;

DO $$
DECLARE
    concept_kind "char";
BEGIN
    SELECT c.relkind INTO concept_kind
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'wintehr_cdm' AND c.relname = 'concept';

    IF to_regclass('omop_vocab.concept') IS NULL THEN
        RAISE EXCEPTION 'omop_vocab.concept is missing';
    END IF;

    IF concept_kind = 'r' THEN
        IF EXISTS (SELECT 1 FROM wintehr_cdm.concept) THEN
            RAISE EXCEPTION 'wintehr_cdm.concept has rows; refusing to replace it';
        END IF;
        IF to_regclass('wintehr_cdm.concept_empty_backup') IS NOT NULL THEN
            RAISE EXCEPTION 'wintehr_cdm.concept_empty_backup already exists';
        END IF;
        ALTER TABLE wintehr_cdm.concept RENAME TO concept_empty_backup;
        CREATE VIEW wintehr_cdm.concept AS SELECT * FROM omop_vocab.concept;
    ELSIF concept_kind = 'v' THEN
        IF position('omop_vocab.concept' IN pg_get_viewdef('wintehr_cdm.concept'::regclass)) = 0 THEN
            RAISE EXCEPTION 'wintehr_cdm.concept is a view of another source';
        END IF;
    ELSE
        RAISE EXCEPTION 'Expected wintehr_cdm.concept to be a table or view, found %', concept_kind;
    END IF;

    IF (SELECT count(*) FROM wintehr_cdm.concept WHERE concept_id IN (8507, 8532)) <> 2 THEN
        RAISE EXCEPTION 'WintEHR CDM concept view cannot resolve gender concepts';
    END IF;
END
$$;

COMMIT;
