-- Only local, non-secret invocation settings cross from Gradle into SQL.
CREATE SCHEMA runtime;
-- Leere optionale Ausgabetexte bedeuten «Serienwert verwenden». Nichtleere Texte
-- bleiben unverändert; wir kürzen keine fachlich gewollten Abstände oder Absätze.
CREATE MACRO runtime.text_or_parent(value, parent) AS
 CASE WHEN value IS NULL OR regexp_full_match(value, '\s*') THEN parent ELSE value END;
CREATE TABLE runtime.parameters AS
SELECT * REPLACE (CAST(today AS DATE) AS today),
 dataset || '_issue_' || substr(sha256(issue),1,24) AS provisional_id,
 ''::VARCHAR AS file_stem, 0::BIGINT AS object_count, 0::INTEGER AS attribute_count
FROM read_json(${parameters_file});
CREATE TABLE runtime.selection AS SELECT dataset,replace_metadata FROM runtime.parameters;
CREATE TABLE runtime.configuration AS SELECT * FROM read_json(${mappings_file});
CREATE TABLE runtime.theme_mapping AS SELECT substr(key,7) AS code,value AS uri FROM runtime.configuration WHERE starts_with(key,'theme.');
CREATE TABLE runtime.access_mapping AS SELECT substr(key,8) AS code,value AS uri FROM runtime.configuration WHERE starts_with(key,'access.');
CREATE TABLE runtime.frequency_mapping AS SELECT substr(key,11) AS code,value AS uri FROM runtime.configuration WHERE starts_with(key,'frequency.');
SELECT CASE WHEN NOT p.bootstrap AND
 ((SELECT count(*) FROM incoming.dataset)<>1 OR
  NOT EXISTS(SELECT 1 FROM incoming.dataset i WHERE i.identifier=p.dataset
             AND (i.t_type='datasetseries')=p.is_series))
 THEN error('Metadata identifier and Dataset/DatasetSeries type must match the selected topic; exactly one topic is required.') ELSE true END
FROM runtime.parameters p;
SELECT CASE WHEN length(issue)>100 THEN error('Ausgabe exceeds the PublishedCatalog limit of 100 characters.') ELSE true END FROM runtime.parameters;
