-- Mapping verified against the pinned Datasheet model with createBasketCol/coalesceJson.
-- Input schemas remain untouched. A delivered root replaces one complete metadata tree.
CREATE SCHEMA merge_work;
SELECT CASE WHEN EXISTS(SELECT 1 FROM incoming.dataset i JOIN repository.dataset r USING(identifier) WHERE i.t_type<>r.t_type)
 THEN error('Dataset/DatasetSeries type must not change') ELSE true END;
CREATE TABLE merge_work.replace_root AS
 SELECT r.t_id FROM repository.dataset r JOIN incoming.dataset i USING(identifier)
 CROSS JOIN runtime.selection p WHERE p.replace_metadata;
CREATE TABLE merge_work.replace_issue AS
 SELECT t_id FROM repository.datasetissue WHERE dataset_issues IN (SELECT t_id FROM merge_work.replace_root);
CREATE TABLE merge_work.offset_value AS SELECT coalesce(max(id),0)+1000 AS n FROM (
SELECT t_id AS id FROM repository.contactpoint
UNION ALL
SELECT t_id AS id FROM repository.dataset
UNION ALL
SELECT t_id AS id FROM repository.dataset_keywords
UNION ALL
SELECT t_id AS id FROM repository.dataset_themes
UNION ALL
SELECT t_id AS id FROM repository.datasetattribute
UNION ALL
SELECT t_id AS id FROM repository.datasetissue
UNION ALL
SELECT t_id AS id FROM repository.temporalcoverage);
INSERT INTO sheets.contactpoint SELECT * FROM repository.contactpoint WHERE (dataset_contactpoint IS NULL OR dataset_contactpoint NOT IN (SELECT t_id FROM merge_work.replace_root));
INSERT INTO sheets.contactpoint SELECT x.* REPLACE (x.t_id+o.n AS t_id, x.t_basket+o.n AS t_basket, x.dataset_contactpoint+o.n AS dataset_contactpoint) FROM incoming.contactpoint x CROSS JOIN merge_work.offset_value o
 WHERE (SELECT replace_metadata FROM runtime.selection) OR NOT EXISTS (SELECT 1 FROM repository.dataset WHERE identifier=(SELECT dataset FROM runtime.selection));
INSERT INTO sheets.dataset SELECT * FROM repository.dataset WHERE t_id NOT IN (SELECT t_id FROM merge_work.replace_root);
INSERT INTO sheets.dataset SELECT x.* REPLACE (x.t_id+o.n AS t_id, x.t_basket+o.n AS t_basket) FROM incoming.dataset x CROSS JOIN merge_work.offset_value o
 WHERE (SELECT replace_metadata FROM runtime.selection) OR NOT EXISTS (SELECT 1 FROM repository.dataset WHERE identifier=(SELECT dataset FROM runtime.selection));
INSERT INTO sheets.dataset_keywords SELECT * FROM repository.dataset_keywords WHERE (dataset_keywords IS NULL OR dataset_keywords NOT IN (SELECT t_id FROM merge_work.replace_root));
INSERT INTO sheets.dataset_keywords SELECT x.* REPLACE (x.t_id+o.n AS t_id, x.t_basket+o.n AS t_basket, x.dataset_keywords+o.n AS dataset_keywords) FROM incoming.dataset_keywords x CROSS JOIN merge_work.offset_value o
 WHERE (SELECT replace_metadata FROM runtime.selection) OR NOT EXISTS (SELECT 1 FROM repository.dataset WHERE identifier=(SELECT dataset FROM runtime.selection));
INSERT INTO sheets.dataset_themes SELECT * FROM repository.dataset_themes WHERE (dataset_themes IS NULL OR dataset_themes NOT IN (SELECT t_id FROM merge_work.replace_root));
INSERT INTO sheets.dataset_themes SELECT x.* REPLACE (x.t_id+o.n AS t_id, x.t_basket+o.n AS t_basket, x.dataset_themes+o.n AS dataset_themes) FROM incoming.dataset_themes x CROSS JOIN merge_work.offset_value o
 WHERE (SELECT replace_metadata FROM runtime.selection) OR NOT EXISTS (SELECT 1 FROM repository.dataset WHERE identifier=(SELECT dataset FROM runtime.selection));
INSERT INTO sheets.datasetattribute SELECT * FROM repository.datasetattribute WHERE (dataset_attributes IS NULL OR dataset_attributes NOT IN (SELECT t_id FROM merge_work.replace_root)) AND (datasetissue_attributes IS NULL OR datasetissue_attributes NOT IN (SELECT t_id FROM merge_work.replace_issue));
INSERT INTO sheets.datasetattribute SELECT x.* REPLACE (x.t_id+o.n AS t_id, x.t_basket+o.n AS t_basket, x.dataset_attributes+o.n AS dataset_attributes, x.datasetissue_attributes+o.n AS datasetissue_attributes) FROM incoming.datasetattribute x CROSS JOIN merge_work.offset_value o
 WHERE (SELECT replace_metadata FROM runtime.selection) OR NOT EXISTS (SELECT 1 FROM repository.dataset WHERE identifier=(SELECT dataset FROM runtime.selection));
INSERT INTO sheets.datasetissue SELECT * FROM repository.datasetissue WHERE (dataset_issues IS NULL OR dataset_issues NOT IN (SELECT t_id FROM merge_work.replace_root));
INSERT INTO sheets.datasetissue SELECT x.* REPLACE (x.t_id+o.n AS t_id, x.t_basket+o.n AS t_basket, x.dataset_issues+o.n AS dataset_issues) FROM incoming.datasetissue x CROSS JOIN merge_work.offset_value o
 WHERE (SELECT replace_metadata FROM runtime.selection) OR NOT EXISTS (SELECT 1 FROM repository.dataset WHERE identifier=(SELECT dataset FROM runtime.selection));
INSERT INTO sheets.temporalcoverage SELECT * FROM repository.temporalcoverage WHERE (dataset_temporalcoverage IS NULL OR dataset_temporalcoverage NOT IN (SELECT t_id FROM merge_work.replace_root)) AND (datasetissue_temporalcoverage IS NULL OR datasetissue_temporalcoverage NOT IN (SELECT t_id FROM merge_work.replace_issue));
INSERT INTO sheets.temporalcoverage SELECT x.* REPLACE (x.t_id+o.n AS t_id, x.t_basket+o.n AS t_basket, x.dataset_temporalcoverage+o.n AS dataset_temporalcoverage, x.datasetissue_temporalcoverage+o.n AS datasetissue_temporalcoverage) FROM incoming.temporalcoverage x CROSS JOIN merge_work.offset_value o
 WHERE (SELECT replace_metadata FROM runtime.selection) OR NOT EXISTS (SELECT 1 FROM repository.dataset WHERE identifier=(SELECT dataset FROM runtime.selection));
-- One ili2db dataset/basket per business root permits the selected-sheet export.
CREATE TABLE merge_work.baskets AS SELECT t_id AS root_id,identifier,row_number() OVER(ORDER BY identifier)*2 AS basket_id FROM sheets.dataset;
INSERT INTO sheets.t_ili2db_dataset(t_id,datasetname) SELECT basket_id-1,identifier FROM merge_work.baskets;
INSERT INTO sheets.t_ili2db_basket(t_id,dataset,topic,t_ili_tid,attachmentkey)
 SELECT basket_id,basket_id-1,'SO_AGI_DataCatalog_Datasheet_20260523.Metadata','b_'||substr(sha256(identifier),1,24),identifier FROM merge_work.baskets;
UPDATE sheets.dataset d SET t_basket=b.basket_id,t_ili_tid='d_'||substr(sha256(d.identifier),1,24) FROM merge_work.baskets b WHERE b.root_id=d.t_id;
UPDATE sheets.datasetissue i SET t_basket=d.t_basket FROM sheets.dataset d WHERE i.dataset_issues=d.t_id;
UPDATE sheets.contactpoint x SET t_basket=p.t_basket FROM sheets.dataset p WHERE x.dataset_contactpoint=p.t_id;
UPDATE sheets.dataset_keywords x SET t_basket=p.t_basket FROM sheets.dataset p WHERE x.dataset_keywords=p.t_id;
UPDATE sheets.dataset_themes x SET t_basket=p.t_basket FROM sheets.dataset p WHERE x.dataset_themes=p.t_id;
UPDATE sheets.datasetattribute x SET t_basket=p.t_basket FROM sheets.dataset p WHERE x.dataset_attributes=p.t_id;
UPDATE sheets.datasetattribute x SET t_basket=p.t_basket FROM sheets.datasetissue p WHERE x.datasetissue_attributes=p.t_id;
UPDATE sheets.temporalcoverage x SET t_basket=p.t_basket FROM sheets.dataset p WHERE x.dataset_temporalcoverage=p.t_id;
UPDATE sheets.temporalcoverage x SET t_basket=p.t_basket FROM sheets.datasetissue p WHERE x.datasetissue_temporalcoverage=p.t_id;
SELECT CASE WHEN EXISTS(SELECT 1 FROM sheets.dataset GROUP BY identifier HAVING count(*)>1) THEN error('Duplicate topic identifiers') ELSE true END;
