-- Publication assembly for the pinned ili2duckdb schema. All IDs are local to this fresh database.
CREATE SCHEMA work;
CREATE SEQUENCE work.ids START 100000;
CREATE TABLE work.current AS
SELECT CASE WHEN d.t_type='datasetseries' THEN 'S' ELSE 'D' END AS kind,
       d.identifier AS topic, ''::VARCHAR AS label, d.t_id AS sheet_parent,
       NULL::BIGINT AS sheet_issue, d.publicationstatus, false AS current_issue,
       d.creatorref, d.accesslevel, d.accrualperiodicity,
       d.identifier, d.title, d.adescription, d.issued, d.modified, d.model, d.surveymethod, d.dataavailablefrom, d.furtheruses, d.auxiliarydata FROM sheets.dataset d
UNION ALL
SELECT 'I', d.identifier, i.issuelabel, d.t_id, i.t_id,
       CASE WHEN d.publicationstatus='published' THEN i.publicationstatus ELSE d.publicationstatus END,
       i.iscurrentissue, d.creatorref, d.accesslevel, coalesce(i.accrualperiodicity,d.accrualperiodicity),
       i.identifier, runtime.text_or_parent(i.title,d.title||' '||i.issuelabel), runtime.text_or_parent(i.adescription,d.adescription),
       i.issued, coalesce(i.modified,d.modified), runtime.text_or_parent(i.model,d.model),
       runtime.text_or_parent(i.surveymethod,d.surveymethod), runtime.text_or_parent(i.dataavailablefrom,d.dataavailablefrom),
       runtime.text_or_parent(i.furtheruses,d.furtheruses), runtime.text_or_parent(i.auxiliarydata,d.auxiliarydata)
FROM sheets.datasetissue i JOIN sheets.dataset d ON i.dataset_issues=d.t_id;
-- A missing issue is retained in the catalog, never inserted into the datasheet.
INSERT INTO work.current
SELECT 'I',d.identifier,p.issue,d.t_id,NULL,'in_review',false,d.creatorref,d.accesslevel,d.accrualperiodicity,
       p.provisional_id,d.title||' '||p.issue,d.adescription,NULL,d.modified,d.model,d.surveymethod,
       d.dataavailablefrom,d.furtheruses,d.auxiliarydata
FROM sheets.dataset d CROSS JOIN runtime.parameters p
WHERE p.has_data AND p.is_series AND d.identifier=p.dataset
AND NOT EXISTS(SELECT 1 FROM work.current c WHERE c.kind='I' AND c.topic=p.dataset AND c.label=p.issue);
CREATE TABLE work.old AS
SELECT CASE WHEN d.datasetseries_issues IS NULL THEN 'D' ELSE 'I' END AS kind,
       coalesce(s.identifier,d.identifier) AS topic, coalesce(d.issuelabel,'') AS label,
       d.t_id AS old_id, d.identifier, d.title, d.adescription, d.issued, d.modified, d.model, d.surveymethod, d.dataavailablefrom, d.furtheruses, d.auxiliarydata
FROM previous.dataset d LEFT JOIN previous.datasetseries s ON d.datasetseries_issues=s.t_id
UNION ALL SELECT 'S',s.identifier,'',s.t_id,s.identifier, s.title, s.adescription, s.issued, s.modified, s.model, s.surveymethod, s.dataavailablefrom, s.furtheruses, s.auxiliarydata FROM previous.datasetseries s;
CREATE TABLE work.keys AS
SELECT kind,topic,label FROM work.old
UNION
SELECT c.kind,c.topic,c.label FROM work.current c CROSS JOIN runtime.parameters p
WHERE p.has_data AND c.topic=p.dataset AND
 ((NOT p.is_series AND c.kind='D') OR (p.is_series AND (c.kind='S' OR c.kind='I' AND c.label=p.issue)));
CREATE TABLE work.resources AS
SELECT row_number() OVER(ORDER BY k.topic,k.kind,k.label)+100 AS id,
       k.kind,k.topic,k.label,o.old_id,c.sheet_parent,c.sheet_issue,
       c.creatorref,c.accesslevel,c.accrualperiodicity,
       coalesce(c.identifier,o.identifier) AS identifier,
       coalesce(c.title,o.title) AS title,coalesce(c.adescription,o.adescription) AS adescription,
       coalesce(c.publicationstatus,'in_review') AS publicationstatus,
       coalesce(c.current_issue,false) AS current_issue,
       p.has_data AND k.topic=p.dataset AND (k.kind IN ('D','S') OR k.label=p.issue) AS delivered,
       coalesce(o.issued,c.issued,CASE WHEN p.has_data AND k.topic=p.dataset AND
          (k.kind IN ('D','S') OR k.label=p.issue) THEN p.today END) AS issued,
       CASE WHEN p.has_data AND k.topic=p.dataset AND (k.kind IN ('D','S') OR k.label=p.issue)
            THEN p.today ELSE coalesce(o.modified,c.modified) END AS modified,
       CASE WHEN c.identifier IS NOT NULL THEN c.model ELSE o.model END AS model, CASE WHEN c.identifier IS NOT NULL THEN c.surveymethod ELSE o.surveymethod END AS surveymethod, CASE WHEN c.identifier IS NOT NULL THEN c.dataavailablefrom ELSE o.dataavailablefrom END AS dataavailablefrom, CASE WHEN c.identifier IS NOT NULL THEN c.furtheruses ELSE o.furtheruses END AS furtheruses, CASE WHEN c.identifier IS NOT NULL THEN c.auxiliarydata ELSE o.auxiliarydata END AS auxiliarydata
FROM work.keys k LEFT JOIN work.current c USING(kind,topic,label)
LEFT JOIN work.old o USING(kind,topic,label) CROSS JOIN runtime.parameters p;
-- Dates on existing metadata are system-owned, including metadata-only deliveries.
UPDATE sheets.dataset d SET issued=coalesce(r.issued,b.issued),
 modified=coalesce(r.modified,b.modified,d.modified)
FROM repository.dataset b LEFT JOIN work.resources r ON r.topic=b.identifier AND r.kind IN ('D','S')
WHERE d.identifier=b.identifier;
UPDATE sheets.datasetissue i SET issued=coalesce(r.issued,b.issued), modified=coalesce(r.modified,b.modified,i.modified)
FROM sheets.dataset d, repository.dataset bd, repository.datasetissue b
LEFT JOIN work.resources r ON r.kind='I' AND r.label=b.issuelabel AND r.topic=(SELECT identifier FROM repository.dataset WHERE t_id=b.dataset_issues)
WHERE i.dataset_issues=d.t_id AND bd.identifier=d.identifier AND b.dataset_issues=bd.t_id AND b.issuelabel=i.issuelabel;
-- Newly documented issues inherit dates of earlier unlisted deliveries.
UPDATE sheets.datasetissue i SET issued=r.issued, modified=r.modified
FROM sheets.dataset d, work.resources r
WHERE i.dataset_issues=d.t_id AND r.kind='I' AND r.topic=d.identifier AND r.label=i.issuelabel;
INSERT INTO candidate.t_ili2db_dataset(t_id,datasetname) VALUES(1,'catalog');
INSERT INTO candidate.t_ili2db_basket(t_id,dataset,topic,t_ili_tid,attachmentkey)
VALUES(2,1,'SO_AGI_DataCatalog_PublishedCatalog_20260602.Publication','catalog_basket','catalog');
INSERT INTO candidate.acatalog(t_id,t_basket,t_ili_tid,cataloguri,title,adescription,homepage,modified)
SELECT 3,2,'catalog',base_uri||'/catalog',catalog_title,catalog_description,base_uri,
 coalesce((SELECT max(modified) FROM work.resources),today) FROM runtime.parameters;

INSERT INTO candidate.datasetseries(t_id,t_basket,t_seq,resourceuri,identifier,title,adescription,landingpage,issued,modified,publicationstatus,model,surveymethod,dataavailablefrom,furtheruses,auxiliarydata,acatalog_datasetseries)
SELECT r.id,2,r.id,p.base_uri||'/dataset/'||url_encode(r.identifier),r.identifier,r.title,r.adescription,p.base_uri||CASE r.kind WHEN 'S' THEN p.series_path||url_encode(r.identifier) WHEN 'I' THEN p.series_path||url_encode(r.topic)||p.issue_path||url_encode(r.identifier) ELSE p.dataset_path||url_encode(r.identifier) END,r.issued,r.modified,r.publicationstatus,r.model,r.surveymethod,r.dataavailablefrom,r.furtheruses,r.auxiliarydata,3
FROM work.resources r CROSS JOIN runtime.parameters p LEFT JOIN work.resources s ON s.kind='S' AND s.topic=r.topic WHERE r.kind='S';

INSERT INTO candidate.dataset(t_id,t_basket,t_seq,resourceuri,identifier,title,adescription,landingpage,issued,modified,publicationstatus,model,surveymethod,dataavailablefrom,furtheruses,auxiliarydata,t_type,issuelabel,iscurrentissue,datasetseries_issues,acatalog_datasets)
SELECT r.id,2,r.id,p.base_uri||'/dataset/'||url_encode(r.identifier),r.identifier,r.title,r.adescription,p.base_uri||CASE r.kind WHEN 'S' THEN p.series_path||url_encode(r.identifier) WHEN 'I' THEN p.series_path||url_encode(r.topic)||p.issue_path||url_encode(r.identifier) ELSE p.dataset_path||url_encode(r.identifier) END,r.issued,r.modified,r.publicationstatus,r.model,r.surveymethod,r.dataavailablefrom,r.furtheruses,r.auxiliarydata,CASE WHEN r.kind='I' THEN 'datasetissue' ELSE 'dataset' END,NULLIF(r.label,''),r.current_issue,s.id,CASE WHEN r.kind='D' THEN 3 END
FROM work.resources r CROSS JOIN runtime.parameters p LEFT JOIN work.resources s ON s.kind='S' AND s.topic=r.topic WHERE r.kind IN ('D','I');

-- These fields do not exist in the Datasheet model, so retain the accepted catalog values.
UPDATE candidate.datasetseries d SET licenseuri=o.licenseuri, origin=o.origin
FROM work.resources r JOIN previous.datasetseries o ON o.t_id=r.old_id WHERE d.t_id=r.id;
UPDATE candidate.dataset d SET licenseuri=o.licenseuri, origin=o.origin
FROM work.resources r JOIN previous.dataset o ON o.t_id=r.old_id WHERE d.t_id=r.id;
UPDATE candidate.dataset d SET licenseuri=s.licenseuri, origin=s.origin
FROM work.resources r, candidate.datasetseries s
WHERE d.t_id=r.id AND r.old_id IS NULL AND d.datasetseries_issues=s.t_id;

INSERT INTO candidate.contactpoint(t_id,t_basket,t_seq,aname,organizationunit,email,phone,url,datasetseries_contactpoint)
SELECT nextval('work.ids'),2,x.t_seq,x.aname,x.organizationunit,x.email,x.phone,x.url,r.id
FROM work.resources r JOIN sheets.contactpoint x ON x.dataset_contactpoint=r.sheet_parent WHERE r.kind='S';
INSERT INTO candidate.contactpoint(t_id,t_basket,t_seq,aname,organizationunit,email,phone,url,datasetseries_contactpoint)
SELECT nextval('work.ids'),2,x.t_seq,x.aname,x.organizationunit,x.email,x.phone,x.url,r.id
FROM work.resources r JOIN previous.contactpoint x ON x.datasetseries_contactpoint=r.old_id
WHERE r.kind='S' AND r.sheet_parent IS NULL;

INSERT INTO candidate.contactpoint(t_id,t_basket,t_seq,aname,organizationunit,email,phone,url,dataset_contactpoint)
SELECT nextval('work.ids'),2,x.t_seq,x.aname,x.organizationunit,x.email,x.phone,x.url,r.id
FROM work.resources r JOIN sheets.contactpoint x ON x.dataset_contactpoint=r.sheet_parent WHERE r.kind IN ('D','I');
INSERT INTO candidate.contactpoint(t_id,t_basket,t_seq,aname,organizationunit,email,phone,url,dataset_contactpoint)
SELECT nextval('work.ids'),2,x.t_seq,x.aname,x.organizationunit,x.email,x.phone,x.url,r.id
FROM work.resources r JOIN previous.contactpoint x ON x.dataset_contactpoint=r.old_id
WHERE r.kind IN ('D','I') AND r.sheet_parent IS NULL;

INSERT INTO candidate.datasetattribute(t_id,t_basket,t_seq,aname,datatype,adescription,unit,codelist,mandatory,datasetseries_attributes)
SELECT nextval('work.ids'),2,x.t_seq,x.aname,x.datatype,x.adescription,x.unit,x.codelist,x.mandatory,r.id
FROM work.resources r JOIN sheets.datasetattribute x ON (x.datasetissue_attributes=r.sheet_issue OR x.dataset_attributes=r.sheet_parent AND NOT EXISTS(SELECT 1 FROM sheets.datasetattribute own WHERE own.datasetissue_attributes=r.sheet_issue)) WHERE r.kind='S';
INSERT INTO candidate.datasetattribute(t_id,t_basket,t_seq,aname,datatype,adescription,unit,codelist,mandatory,datasetseries_attributes)
SELECT nextval('work.ids'),2,x.t_seq,x.aname,x.datatype,x.adescription,x.unit,x.codelist,x.mandatory,r.id
FROM work.resources r JOIN previous.datasetattribute x ON x.datasetseries_attributes=r.old_id
WHERE r.kind='S' AND r.sheet_parent IS NULL;

INSERT INTO candidate.datasetattribute(t_id,t_basket,t_seq,aname,datatype,adescription,unit,codelist,mandatory,dataset_attributes)
SELECT nextval('work.ids'),2,x.t_seq,x.aname,x.datatype,x.adescription,x.unit,x.codelist,x.mandatory,r.id
FROM work.resources r JOIN sheets.datasetattribute x ON (x.datasetissue_attributes=r.sheet_issue OR x.dataset_attributes=r.sheet_parent AND NOT EXISTS(SELECT 1 FROM sheets.datasetattribute own WHERE own.datasetissue_attributes=r.sheet_issue)) WHERE r.kind IN ('D','I');
INSERT INTO candidate.datasetattribute(t_id,t_basket,t_seq,aname,datatype,adescription,unit,codelist,mandatory,dataset_attributes)
SELECT nextval('work.ids'),2,x.t_seq,x.aname,x.datatype,x.adescription,x.unit,x.codelist,x.mandatory,r.id
FROM work.resources r JOIN previous.datasetattribute x ON x.dataset_attributes=r.old_id
WHERE r.kind IN ('D','I') AND r.sheet_parent IS NULL;

INSERT INTO candidate.temporalcoverage(t_id,t_basket,t_seq,startdate,enddate,referencedate,datasetseries_temporalcoverage)
SELECT nextval('work.ids'),2,x.t_seq,x.startdate,x.enddate,x.referencedate,r.id
FROM work.resources r JOIN sheets.temporalcoverage x ON (x.datasetissue_temporalcoverage=r.sheet_issue OR x.dataset_temporalcoverage=r.sheet_parent AND NOT EXISTS(SELECT 1 FROM sheets.temporalcoverage own WHERE own.datasetissue_temporalcoverage=r.sheet_issue)) WHERE r.kind='S';
INSERT INTO candidate.temporalcoverage(t_id,t_basket,t_seq,startdate,enddate,referencedate,datasetseries_temporalcoverage)
SELECT nextval('work.ids'),2,x.t_seq,x.startdate,x.enddate,x.referencedate,r.id
FROM work.resources r JOIN previous.temporalcoverage x ON x.datasetseries_temporalcoverage=r.old_id
WHERE r.kind='S' AND r.sheet_parent IS NULL;

INSERT INTO candidate.temporalcoverage(t_id,t_basket,t_seq,startdate,enddate,referencedate,dataset_temporalcoverage)
SELECT nextval('work.ids'),2,x.t_seq,x.startdate,x.enddate,x.referencedate,r.id
FROM work.resources r JOIN sheets.temporalcoverage x ON (x.datasetissue_temporalcoverage=r.sheet_issue OR x.dataset_temporalcoverage=r.sheet_parent AND NOT EXISTS(SELECT 1 FROM sheets.temporalcoverage own WHERE own.datasetissue_temporalcoverage=r.sheet_issue)) WHERE r.kind IN ('D','I');
INSERT INTO candidate.temporalcoverage(t_id,t_basket,t_seq,startdate,enddate,referencedate,dataset_temporalcoverage)
SELECT nextval('work.ids'),2,x.t_seq,x.startdate,x.enddate,x.referencedate,r.id
FROM work.resources r JOIN previous.temporalcoverage x ON x.dataset_temporalcoverage=r.old_id
WHERE r.kind IN ('D','I') AND r.sheet_parent IS NULL;

INSERT INTO candidate.datasetseries_keywords(t_id,t_basket,t_seq,datasetseries_keywords,keywords)
SELECT nextval('work.ids'),2,x.t_seq,r.id,x.keywords FROM work.resources r
JOIN sheets.dataset_keywords x ON x.dataset_keywords=r.sheet_parent WHERE r.kind='S';
INSERT INTO candidate.datasetseries_keywords(t_id,t_basket,t_seq,datasetseries_keywords,keywords)
SELECT nextval('work.ids'),2,x.t_seq,r.id,x.keywords FROM work.resources r
JOIN previous.datasetseries_keywords x ON x.datasetseries_keywords=r.old_id WHERE r.kind='S' AND r.sheet_parent IS NULL;
INSERT INTO candidate.themeassignment(t_id,t_basket,t_seq,localtheme,themeuri,datasetseries_themes)
SELECT nextval('work.ids'),2,x.t_seq,x.themes,m.uri,r.id FROM work.resources r
JOIN sheets.dataset_themes x ON x.dataset_themes=r.sheet_parent JOIN runtime.theme_mapping m ON m.code=x.themes WHERE r.kind='S';
INSERT INTO candidate.themeassignment(t_id,t_basket,t_seq,localtheme,themeuri,datasetseries_themes)
SELECT nextval('work.ids'),2,x.t_seq,x.localtheme,x.themeuri,r.id FROM work.resources r
JOIN previous.themeassignment x ON x.datasetseries_themes=r.old_id WHERE r.kind='S' AND r.sheet_parent IS NULL;
INSERT INTO candidate.accessrights(t_id,t_basket,t_seq,localaccesslevel,accessrightsuri,datasetseries_accessrights)
SELECT nextval('work.ids'),2,1,r.accesslevel,m.uri,r.id FROM work.resources r
JOIN runtime.access_mapping m ON m.code=r.accesslevel WHERE r.kind='S';
INSERT INTO candidate.accessrights(t_id,t_basket,t_seq,localaccesslevel,accessrightsuri,datasetseries_accessrights)
SELECT nextval('work.ids'),2,1,x.localaccesslevel,x.accessrightsuri,r.id FROM work.resources r
JOIN previous.accessrights x ON x.datasetseries_accessrights=r.old_id WHERE r.kind='S' AND r.sheet_parent IS NULL;
INSERT INTO candidate.accrualperiodicity(t_id,t_basket,t_seq,localfrequency,frequencyuri,datasetseries_accrualperiodicity)
SELECT nextval('work.ids'),2,1,r.accrualperiodicity,m.uri,r.id FROM work.resources r
JOIN runtime.frequency_mapping m ON m.code=r.accrualperiodicity WHERE r.kind='S';
INSERT INTO candidate.accrualperiodicity(t_id,t_basket,t_seq,localfrequency,frequencyuri,datasetseries_accrualperiodicity)
SELECT nextval('work.ids'),2,1,x.localfrequency,x.frequencyuri,r.id FROM work.resources r
JOIN previous.accrualperiodicity x ON x.datasetseries_accrualperiodicity=r.old_id WHERE r.kind='S' AND r.sheet_parent IS NULL;

INSERT INTO candidate.office(t_id,t_basket,t_seq,officeuri,aname,abbreviation,email,officeatweb,datasetseries_creator)
SELECT nextval('work.ids'),2,1,p.base_uri||'/agent/'||o.identifier,o.aname,o.abbreviation,o.email,o.officeatweb,r.id
FROM work.resources r CROSS JOIN runtime.parameters p JOIN offices.office o ON o.identifier=r.creatorref WHERE r.kind='S';

INSERT INTO candidate.office(t_id,t_basket,t_seq,officeuri,aname,abbreviation,email,officeatweb,datasetseries_creator)
SELECT nextval('work.ids'),2,1,x.officeuri,x.aname,x.abbreviation,x.email,x.officeatweb,r.id
FROM work.resources r JOIN previous.office x ON x.datasetseries_creator=r.old_id WHERE r.kind='S' AND r.sheet_parent IS NULL;

INSERT INTO candidate.office(t_id,t_basket,t_seq,officeuri,aname,abbreviation,email,officeatweb,datasetseries_publisher)
SELECT nextval('work.ids'),2,1,p.base_uri||'/agent/'||o.identifier,o.aname,o.abbreviation,o.email,o.officeatweb,r.id
FROM work.resources r CROSS JOIN runtime.parameters p JOIN offices.office o ON o.identifier=p.publisher WHERE r.kind='S';

INSERT INTO candidate.qualitysummary(t_id,t_basket,t_seq,astatus,aerrors,validatedat,reporturl,datasetseries_qualitysummary)
SELECT nextval('work.ids'),2,1,x.astatus,x.aerrors,x.validatedat,x.reporturl,r.id FROM work.resources r
JOIN previous.qualitysummary x ON x.datasetseries_qualitysummary=r.old_id WHERE r.kind='S' AND NOT r.delivered;

INSERT INTO candidate.dataset_keywords(t_id,t_basket,t_seq,dataset_keywords,keywords)
SELECT nextval('work.ids'),2,x.t_seq,r.id,x.keywords FROM work.resources r
JOIN sheets.dataset_keywords x ON x.dataset_keywords=r.sheet_parent WHERE r.kind IN ('D','I');
INSERT INTO candidate.dataset_keywords(t_id,t_basket,t_seq,dataset_keywords,keywords)
SELECT nextval('work.ids'),2,x.t_seq,r.id,x.keywords FROM work.resources r
JOIN previous.dataset_keywords x ON x.dataset_keywords=r.old_id WHERE r.kind IN ('D','I') AND r.sheet_parent IS NULL;
INSERT INTO candidate.themeassignment(t_id,t_basket,t_seq,localtheme,themeuri,dataset_themes)
SELECT nextval('work.ids'),2,x.t_seq,x.themes,m.uri,r.id FROM work.resources r
JOIN sheets.dataset_themes x ON x.dataset_themes=r.sheet_parent JOIN runtime.theme_mapping m ON m.code=x.themes WHERE r.kind IN ('D','I');
INSERT INTO candidate.themeassignment(t_id,t_basket,t_seq,localtheme,themeuri,dataset_themes)
SELECT nextval('work.ids'),2,x.t_seq,x.localtheme,x.themeuri,r.id FROM work.resources r
JOIN previous.themeassignment x ON x.dataset_themes=r.old_id WHERE r.kind IN ('D','I') AND r.sheet_parent IS NULL;
INSERT INTO candidate.accessrights(t_id,t_basket,t_seq,localaccesslevel,accessrightsuri,dataset_accessrights)
SELECT nextval('work.ids'),2,1,r.accesslevel,m.uri,r.id FROM work.resources r
JOIN runtime.access_mapping m ON m.code=r.accesslevel WHERE r.kind IN ('D','I');
INSERT INTO candidate.accessrights(t_id,t_basket,t_seq,localaccesslevel,accessrightsuri,dataset_accessrights)
SELECT nextval('work.ids'),2,1,x.localaccesslevel,x.accessrightsuri,r.id FROM work.resources r
JOIN previous.accessrights x ON x.dataset_accessrights=r.old_id WHERE r.kind IN ('D','I') AND r.sheet_parent IS NULL;
INSERT INTO candidate.accrualperiodicity(t_id,t_basket,t_seq,localfrequency,frequencyuri,dataset_accrualperiodicity)
SELECT nextval('work.ids'),2,1,r.accrualperiodicity,m.uri,r.id FROM work.resources r
JOIN runtime.frequency_mapping m ON m.code=r.accrualperiodicity WHERE r.kind IN ('D','I');
INSERT INTO candidate.accrualperiodicity(t_id,t_basket,t_seq,localfrequency,frequencyuri,dataset_accrualperiodicity)
SELECT nextval('work.ids'),2,1,x.localfrequency,x.frequencyuri,r.id FROM work.resources r
JOIN previous.accrualperiodicity x ON x.dataset_accrualperiodicity=r.old_id WHERE r.kind IN ('D','I') AND r.sheet_parent IS NULL;

INSERT INTO candidate.office(t_id,t_basket,t_seq,officeuri,aname,abbreviation,email,officeatweb,dataset_creator)
SELECT nextval('work.ids'),2,1,p.base_uri||'/agent/'||o.identifier,o.aname,o.abbreviation,o.email,o.officeatweb,r.id
FROM work.resources r CROSS JOIN runtime.parameters p JOIN offices.office o ON o.identifier=r.creatorref WHERE r.kind IN ('D','I');

INSERT INTO candidate.office(t_id,t_basket,t_seq,officeuri,aname,abbreviation,email,officeatweb,dataset_creator)
SELECT nextval('work.ids'),2,1,x.officeuri,x.aname,x.abbreviation,x.email,x.officeatweb,r.id
FROM work.resources r JOIN previous.office x ON x.dataset_creator=r.old_id WHERE r.kind IN ('D','I') AND r.sheet_parent IS NULL;

INSERT INTO candidate.office(t_id,t_basket,t_seq,officeuri,aname,abbreviation,email,officeatweb,dataset_publisher)
SELECT nextval('work.ids'),2,1,p.base_uri||'/agent/'||o.identifier,o.aname,o.abbreviation,o.email,o.officeatweb,r.id
FROM work.resources r CROSS JOIN runtime.parameters p JOIN offices.office o ON o.identifier=p.publisher WHERE r.kind IN ('D','I');

INSERT INTO candidate.qualitysummary(t_id,t_basket,t_seq,astatus,aerrors,validatedat,reporturl,dataset_qualitysummary)
SELECT nextval('work.ids'),2,1,x.astatus,x.aerrors,x.validatedat,x.reporturl,r.id FROM work.resources r
JOIN previous.qualitysummary x ON x.dataset_qualitysummary=r.old_id WHERE r.kind IN ('D','I') AND NOT r.delivered;

INSERT INTO candidate.office(t_id,t_basket,t_seq,officeuri,aname,abbreviation,email,officeatweb,acatalog_publisher)
SELECT nextval('work.ids'),2,row_number() OVER(ORDER BY o.identifier),p.base_uri||'/agent/'||o.identifier,o.aname,o.abbreviation,o.email,o.officeatweb,3
FROM offices.office o CROSS JOIN runtime.parameters p WHERE o.identifier=p.publisher;

INSERT INTO candidate.office(t_id,t_basket,t_seq,officeuri,aname,abbreviation,email,officeatweb,acatalog_agents)
SELECT nextval('work.ids'),2,row_number() OVER(ORDER BY o.identifier),p.base_uri||'/agent/'||o.identifier,o.aname,o.abbreviation,o.email,o.officeatweb,3
FROM offices.office o CROSS JOIN runtime.parameters p ;

-- Refresh known offices even for resources whose datasheet was removed.
UPDATE candidate.office c SET aname=o.aname, abbreviation=o.abbreviation, email=o.email, officeatweb=o.officeatweb
FROM offices.office o CROSS JOIN runtime.parameters p
WHERE c.officeuri=p.base_uri||'/agent/'||o.identifier;

INSERT INTO candidate.structuresummary(t_id,t_basket,t_seq,objectcount,attributecount,dataset_structuresummary)
SELECT nextval('work.ids'),2,1,
 CASE WHEN r.delivered THEN p.object_count ELSE x.objectcount END,
 CASE WHEN r.delivered THEN p.attribute_count ELSE x.attributecount END,r.id
FROM work.resources r CROSS JOIN runtime.parameters p LEFT JOIN previous.structuresummary x ON x.dataset_structuresummary=r.old_id
WHERE r.kind IN ('D','I');
INSERT INTO candidate.structuresummary(t_id,t_basket,t_seq,objectcount,attributecount,datasetseries_structuresummary)
SELECT nextval('work.ids'),2,1,x.objectcount,x.attributecount,s.id
FROM work.resources s JOIN work.resources i ON i.kind='I' AND i.topic=s.topic
JOIN candidate.structuresummary x ON x.dataset_structuresummary=i.id
WHERE s.kind='S'
QUALIFY row_number() OVER(PARTITION BY s.id ORDER BY (i.current_issue AND i.publicationstatus='published') DESC,i.modified DESC,i.identifier)=1;
INSERT INTO candidate.distribution(t_id,t_basket,t_seq,distributionuri,accessurl,downloadurl,aformat,dataset_distributions)
SELECT nextval('work.ids'),2,x.t_seq,x.distributionuri,x.accessurl,x.downloadurl,x.aformat,r.id
FROM work.resources r JOIN previous.distribution x ON x.dataset_distributions=r.old_id WHERE NOT r.delivered;
INSERT INTO candidate.distribution(t_id,t_basket,t_seq,distributionuri,accessurl,downloadurl,aformat,dataset_distributions)
SELECT nextval('work.ids'),2,f.seq,p.base_uri||'/dataset/'||url_encode(r.identifier)||'/distribution/'||f.format,
 p.base_uri||CASE WHEN r.kind='I' THEN p.series_path||url_encode(r.topic)||p.issue_path||url_encode(r.identifier) ELSE p.dataset_path||url_encode(r.identifier) END,coalesce(old.downloadurl,p.download_base||'/'||f.encoded_name),f.format,r.id
FROM work.resources r CROSS JOIN runtime.parameters p CROSS JOIN (SELECT format,encoded_name,CASE format WHEN 'csv' THEN 1 WHEN 'xlsx' THEN 2 ELSE 3 END AS seq FROM runtime.delivery_files) f
LEFT JOIN previous.distribution old ON old.dataset_distributions=r.old_id AND old.aformat=f.format
WHERE r.delivered AND r.kind IN ('D','I');
-- Reject incomplete relations before exporting an XTF candidate.
SELECT CASE WHEN EXISTS(SELECT 1 FROM work.resources GROUP BY identifier HAVING count(*)>1)
 THEN error('Duplicate catalog identifier') ELSE true END;
