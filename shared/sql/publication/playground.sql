-- Public playground view contract. Keep naming in sync with ExploreTableService.
CREATE TABLE work.playground_views AS
WITH urls AS (
    SELECT x.downloadurl AS url
    FROM candidate.distribution x
    JOIN candidate.dataset d ON d.t_id=x.dataset_distributions
    LEFT JOIN candidate.datasetseries s ON s.t_id=d.datasetseries_issues
    WHERE lower(x.aformat)='parquet' AND d.publicationstatus='published'
      AND (d.datasetseries_issues IS NULL OR s.publicationstatus='published')
), paths AS (
    SELECT url, url_decode(regexp_extract(url, '^https?://[^/?#]+([^?#]*)', 1)) AS path FROM urls
)
SELECT url, replace(regexp_replace(regexp_extract(path, '[^/]*$', 0), '\.parquet$', ''), '.', '_') AS name
FROM paths;
SELECT CASE WHEN EXISTS (
    SELECT 1 FROM work.playground_views
    WHERE url IS NULL OR NOT regexp_full_match(url, 'https?://[^/?#@[:space:]]+/[^[:space:]]*')
       OR NOT regexp_full_match(name, '[A-Za-z_][A-Za-z0-9_]*')
) THEN error('Invalid public Parquet URL or playground view name') ELSE true END;
SELECT CASE WHEN EXISTS (
    SELECT 1 FROM work.playground_views GROUP BY lower(name) HAVING count(*)>1
) THEN error('Duplicate playground view name') ELSE true END;
-- COPY emits executable SQL, not CSV-quoted strings. Identifiers were validated;
-- SQL literals are escaped even when URLs contain apostrophes or query parameters.
COPY (
    SELECT statement FROM (
        SELECT -1 AS position, '' AS name, 'SET autoinstall_known_extensions=false;' AS statement
        UNION ALL SELECT 0, '', 'LOAD httpfs;'
        UNION ALL SELECT 1, '', 'CREATE SCHEMA opendata;'
        UNION ALL SELECT 2, name,
            'CREATE VIEW opendata."' || name || '" AS SELECT * FROM read_parquet(' ||
            chr(39) || replace(url, chr(39), chr(39)||chr(39)) || chr(39) || ');'
        FROM work.playground_views
        UNION ALL SELECT 3, name,
            'SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM duckdb_views() WHERE database_name=current_database() AND schema_name=''opendata'' AND view_name=' || chr(39) || name || chr(39) || ') THEN error(''Missing playground view'') ELSE true END;'
        FROM work.playground_views
        UNION ALL SELECT 4, '',
            'SELECT CASE WHEN (SELECT count(*) FROM duckdb_views() WHERE database_name=current_database() AND schema_name=''opendata'') <> ' || count(*) || ' THEN error(''Unexpected playground view count'') ELSE true END;'
        FROM work.playground_views
    ) ORDER BY position, name
) TO ${playground_sql} (FORMAT CSV, HEADER false, QUOTE '', ESCAPE '');
