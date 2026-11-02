COPY (SELECT EXISTS(SELECT 1 FROM work.resources) AS catalogPresent,
 (SELECT count(*) FROM work.playground_views) AS playgroundViewCount,
 object_count AS objectCount,attribute_count AS attributeCount FROM runtime.parameters)
TO ${result_file} (FORMAT JSON, ARRAY true);
