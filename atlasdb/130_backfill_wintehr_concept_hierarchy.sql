-- Ensure Atlas can resolve concept labels used by the WintEHR Achilles reports.
-- WebAPI's generated hierarchy can omit demographic and condition concepts even
-- when the vocabulary and Achilles result rows are present.

INSERT INTO :"results_schema".concept_hierarchy (
    concept_id,
    concept_name,
    treemap,
    concept_hierarchy_type,
    level1_concept_name,
    level2_concept_name,
    level3_concept_name,
    level4_concept_name
)
SELECT
    c.concept_id,
    c.concept_name,
    CASE
        WHEN c.domain_id IN ('Race', 'Ethnicity') THEN 'Person'
        ELSE c.domain_id
    END,
    c.domain_id,
    c.concept_name,
    c.concept_name,
    c.concept_name,
    c.concept_name
FROM :"vocab_schema".concept c
JOIN (
    SELECT DISTINCT CAST(stratum_1 AS integer) AS concept_id
    FROM :"results_schema".achilles_results
    WHERE analysis_id IN (4, 5, 400, 1000)
) used_concepts ON used_concepts.concept_id = c.concept_id
WHERE c.invalid_reason IS NULL
  AND NOT EXISTS (
      SELECT 1
      FROM :"results_schema".concept_hierarchy h
      WHERE h.concept_id = c.concept_id
  );

ANALYZE :"results_schema".concept_hierarchy;
