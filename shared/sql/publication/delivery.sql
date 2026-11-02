-- Resolve the effective issue, model, attributes and accepted distribution names once.
SELECT CASE WHEN EXISTS(SELECT 1 FROM sheets.dataset d LEFT JOIN offices.office o ON o.identifier=d.creatorref WHERE o.t_id IS NULL)
 THEN error('Unknown creatorRef in datasheet collection') ELSE true END;
SELECT CASE WHEN EXISTS(SELECT 1 FROM sheets.datasetissue GROUP BY dataset_issues,issuelabel HAVING count(*)>1)
 THEN error('Duplicate issue labels in datasheet collection') ELSE true END;
SELECT CASE WHEN NOT p.bootstrap AND NOT EXISTS(SELECT 1 FROM sheets.dataset WHERE identifier=p.dataset)
 THEN error('Selected datasheet missing after merge') ELSE true END FROM runtime.parameters p;
CREATE TABLE runtime.selected AS
SELECT d.t_id AS dataset_id,i.t_id AS issue_id,runtime.text_or_parent(i.model,d.model) AS model
FROM runtime.parameters p LEFT JOIN sheets.dataset d ON d.identifier=p.dataset
LEFT JOIN sheets.datasetissue i ON p.has_data AND p.is_series AND i.dataset_issues=d.t_id AND i.issuelabel=p.issue;
CREATE TABLE runtime.attributes AS
SELECT a.*,
 CASE upper(a.datatype) WHEN 'TEXT' THEN 'VARCHAR' WHEN 'INTEGER' THEN 'BIGINT'
 WHEN 'DECIMAL' THEN 'DOUBLE' WHEN 'REAL' THEN 'DOUBLE' WHEN 'DOUBLE' THEN 'DOUBLE'
 WHEN 'NUMERIC' THEN 'DOUBLE' WHEN 'BOOLEAN' THEN 'BOOLEAN' WHEN 'DATE' THEN 'DATE'
 WHEN 'DATETIME' THEN 'TIMESTAMP' END AS sql_type
FROM sheets.datasetattribute a CROSS JOIN runtime.selected s
WHERE a.datasetissue_attributes=s.issue_id OR
 (a.dataset_attributes=s.dataset_id AND NOT EXISTS(SELECT 1 FROM sheets.datasetattribute WHERE datasetissue_attributes=s.issue_id));
SELECT CASE WHEN p.has_data AND EXISTS(SELECT 1 FROM runtime.attributes WHERE sql_type IS NULL)
 THEN error('Unsupported declared CSV datatype') ELSE true END FROM runtime.parameters p;
CREATE MACRO runtime.quote_identifier(value) AS '"'||replace(value,'"','""')||'"';
CREATE MACRO runtime.quote_literal(value) AS ''''||replace(value,'''','''''')||'''';
-- Keep the existing Java form-encoding convention for flat object names.
CREATE MACRO runtime.encode_name(value) AS replace(replace(url_encode(value),'~','%7E'),'%2A','*');
UPDATE runtime.parameters SET file_stem=dataset||CASE WHEN is_series THEN '_'||runtime.encode_name(issue) ELSE '' END;
UPDATE runtime.parameters SET file_stem=left(dataset,120)||'_'||sha256(issue) WHERE octet_length(encode(file_stem))>220;
CREATE TABLE runtime.delivery_files AS
SELECT format,coalesce(url_decode(replace(regexp_extract(old.downloadurl,'^[^?#]*/([^/?#]*)',1),'+','%20')),p.file_stem||'.'||format) AS filename
FROM runtime.parameters p CROSS JOIN (VALUES ('csv'),('xlsx'),('parquet')) f(format)
LEFT JOIN previous.datasetseries s ON p.is_series AND s.identifier=p.dataset
LEFT JOIN previous.dataset d ON (p.is_series AND d.datasetseries_issues=s.t_id AND d.issuelabel=p.issue)
 OR (NOT p.is_series AND d.datasetseries_issues IS NULL AND d.identifier=p.dataset)
LEFT JOIN previous.distribution old ON old.dataset_distributions=d.t_id AND old.aformat=f.format;
SELECT CASE WHEN EXISTS(SELECT 1 FROM runtime.delivery_files WHERE filename IN ('','.','..') OR contains(filename,'/') OR contains(filename,chr(92)))
 THEN error('Unsafe existing distribution filename') ELSE true END;
ALTER TABLE runtime.delivery_files ADD COLUMN encoded_name VARCHAR;
UPDATE runtime.delivery_files SET encoded_name=runtime.encode_name(filename);

-- SQL determines the casts and checks. Gradle only writes this string into convert.sql.
CREATE TABLE runtime.conversion AS
SELECT
 'CREATE TABLE runtime.csv_header AS SELECT json_extract_string(e.value,''$'') AS name,e.id FROM '
 ||'(SELECT * FROM read_csv('||runtime.quote_literal(p.csv_file)||',header=false,all_varchar=true) LIMIT 1) r, json_each(to_json(r)) e;'
 ||'SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM runtime.csv_header) OR EXISTS(SELECT 1 FROM runtime.csv_header WHERE name IS NULL OR trim(name)='''') '
 ||'OR EXISTS(SELECT 1 FROM runtime.csv_header GROUP BY lower(name) HAVING count(*)>1) THEN error(''CSV requires nonempty, unique column names'') ELSE true END;'
 ||coalesce((SELECT 'SELECT CASE WHEN (SELECT list(name ORDER BY id) FROM runtime.csv_header) <> ['
      ||string_agg(runtime.quote_literal(aname),',' ORDER BY t_seq,t_id)||'] THEN error(''CSV columns do not match declared attributes'') ELSE true END;' FROM runtime.attributes),'')
 ||'CREATE SCHEMA data; CREATE TABLE data.records AS SELECT '
 ||coalesce((SELECT string_agg('CAST('||CASE WHEN sql_type='VARCHAR' THEN runtime.quote_identifier(aname)
      ELSE 'NULLIF('||runtime.quote_identifier(aname)||','''')' END||' AS '||sql_type||') AS '||runtime.quote_identifier(aname),',' ORDER BY t_seq,t_id) FROM runtime.attributes),'*')
 ||' FROM csv_input.records;'
 ||coalesce((SELECT string_agg('SELECT CASE WHEN EXISTS(SELECT 1 FROM data.records WHERE '
      ||runtime.quote_identifier(aname)||' IS NULL OR trim(CAST('||runtime.quote_identifier(aname)||' AS VARCHAR))='''') '
      ||'THEN error(''Mandatory CSV column contains null values'') ELSE true END;','' ORDER BY t_seq,t_id)
      FROM runtime.attributes WHERE mandatory),'')
 ||'UPDATE runtime.parameters SET object_count=(SELECT count(*) FROM data.records),attribute_count=(SELECT count(*) FROM information_schema.columns WHERE table_schema=''data'' AND table_name=''records'');' AS sql
FROM runtime.parameters p;
COPY (SELECT s.model,c.sql,
 (SELECT filename FROM runtime.delivery_files WHERE format='csv') AS csv,
 (SELECT filename FROM runtime.delivery_files WHERE format='xlsx') AS xlsx,
 (SELECT filename FROM runtime.delivery_files WHERE format='parquet') AS parquet
 FROM runtime.selected s CROSS JOIN runtime.conversion c) TO ${control_file} (FORMAT JSON, ARRAY true);
