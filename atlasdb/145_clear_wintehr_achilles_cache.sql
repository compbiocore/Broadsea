\set ON_ERROR_STOP on

-- WebAPI's @AchillesCache aspect persists complete Data Sources responses in
-- webapi.achilles_cache. Restarting WebAPI does not invalidate these rows, so
-- remove WINTEHR entries whenever its Achilles results are rebuilt. The next
-- Atlas/WebAPI request recreates each entry from the current results schema.
DELETE FROM webapi.achilles_cache cache
USING webapi.source source
WHERE cache.source_id = source.source_id
  AND source.source_key = 'WINTEHR';
