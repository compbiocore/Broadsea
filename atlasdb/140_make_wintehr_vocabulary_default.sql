\set ON_ERROR_STOP on

-- WebAPI's vocabulary concept endpoints use the highest-priority vocabulary
-- daimon. Atlas does not reliably pass a source key for these requests, so
-- WINTEHR must be the default vocabulary source for the WintEHR deployment.
UPDATE webapi.source_daimon sd
SET priority = 20
FROM webapi.source s
WHERE s.source_id = sd.source_id
  AND s.source_key = 'WINTEHR'
  AND sd.daimon_type = 1;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM webapi.source_daimon sd
    JOIN webapi.source s ON s.source_id = sd.source_id
    WHERE s.source_key = 'WINTEHR'
      AND sd.daimon_type = 1
      AND sd.priority > COALESCE((
        SELECT MAX(other_sd.priority)
        FROM webapi.source_daimon other_sd
        JOIN webapi.source other_s ON other_s.source_id = other_sd.source_id
        WHERE other_sd.daimon_type = 1
          AND other_s.source_key <> 'WINTEHR'
      ), -1)
  ) THEN
    RAISE EXCEPTION 'WINTEHR vocabulary is not the highest-priority WebAPI vocabulary source';
  END IF;
END $$;
