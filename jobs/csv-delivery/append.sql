COPY (
    SELECT * FROM read_csv(${base}, delim = ',', quote = '"', header = true, all_varchar = true)
    UNION ALL BY NAME
    SELECT * FROM read_csv(${incoming}, delim = ',', quote = '"', header = true, all_varchar = true)
) TO ${snapshot} (FORMAT CSV, DELIMITER ',', QUOTE '"', HEADER true);
