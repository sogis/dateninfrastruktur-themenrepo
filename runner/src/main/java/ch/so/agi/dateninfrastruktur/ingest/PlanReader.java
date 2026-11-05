package ch.so.agi.dateninfrastruktur.ingest;

import com.fasterxml.jackson.core.StreamReadFeature;
import com.fasterxml.jackson.databind.*;
import com.fasterxml.jackson.databind.json.JsonMapper;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.util.*;

/** A runner only operates on the versioned model, bound bytes, and server-derived names. */
final class PlanReader {
    static final ObjectMapper JSON=JsonMapper.builder().enable(StreamReadFeature.STRICT_DUPLICATE_DETECTION)
        .enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS).enable(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)
        .enable(SerializationFeature.ORDER_MAP_ENTRIES_BY_KEYS).build();
    static final Set<String> PLAN_FIELDS=Set.of("schemaVersion","submissionId","executionId","fence","initiatorPrincipalId","datasetId","issueId","reservedVersionId","mode","baseVersionId","definitionKey","definitionSha256","modelFiles","modelSetSha256","qualifiedTableName","csvDialect","orderedColumns","rowKeyDefinition","fullSchemaDigest","input","outputs","clickhouse","limits","baseSnapshot","runner");
    final Path run,bundle;
    final JsonNode plan,definition;
    final List<JsonNode> columns;
    final char separator;
    final int cellLimit,rowLimit;
    final long byteLimit;
    final boolean append;
    PlanReader(Path run,Path bundle)throws IOException{
        this.run=run.toRealPath();this.bundle=bundle.toRealPath();
        plan=json(this.run.resolve("plan.json"),131072);
        fields(plan,PLAN_FIELDS);require(plan.path("schemaVersion").asInt()==1 && plan.path("fence").isIntegralNumber()&&plan.path("fence").asLong()>0,"PLAN_BINDING");
        for(String id:List.of("submissionId","executionId","initiatorPrincipalId","datasetId","issueId","reservedVersionId"))uuid(plan,id);
        String definitionKey=plan.path("definitionKey").asText();
        require(definitionKey.matches("[a-z][a-z0-9_-]{0,127}"),"PLAN_BINDING");
        String definitionPath="contracts/"+definitionKey+".json";
        JsonNode index=json(this.bundle.resolve("contracts/index.json"),65536);
        boolean indexed=false;
        for(JsonNode entry:index.path("definitions"))if(definitionPath.equals(entry.path("relativePath").asText()) && plan.path("definitionSha256").equals(entry.path("sha256")))indexed=true;
        require(indexed,"DEFINITION_HASH");
        Path def=this.bundle.resolve(definitionPath);require(sha(def,131072).equals(plan.path("definitionSha256").asText()),"DEFINITION_HASH");
        definition=json(def,131072);
        Map<String,String> bindings=Map.of("definitionKey","definitionKey","qualifiedTableName","qualifiedTableName","modelFiles","modelFiles","modelSetSha256","modelSetSha256","csvDialect","dialect","orderedColumns","columns","rowKeyDefinition","businessKey","limits","limits");
        for(var b:bindings.entrySet())require(plan.get(b.getKey()).equals(definition.get(b.getValue())),"DEFINITION_BINDING");
        var schema=JSON.createObjectNode();schema.put("schemaVersion",1);schema.set("modelSetSha256",plan.get("modelSetSha256"));
        schema.set("table",plan.get("qualifiedTableName"));schema.set("dialect",plan.get("csvDialect"));schema.set("columns",plan.get("orderedColumns"));schema.set("businessKey",plan.get("rowKeyDefinition"));
        require(sha(("di-json-v1\n"+canonical(schema)).getBytes(StandardCharsets.UTF_8)).equals(plan.path("fullSchemaDigest").asText()),"SCHEMA_BINDING");
        var runner=plan.path("runner");fields(runner,Set.of("runnerSha256","repositorySha256","imageSha256"));
        for(var v:runner)require(v.isTextual()&&v.asText().matches("[0-9a-f]{64}"),"PLAN_BINDING");
        verifyModels();
        var dialect=plan.path("csvDialect");String delimiter=dialect.path("separator").asText();require(Set.of(";",",").contains(delimiter),"DIALECT");separator=delimiter.charAt(0);
        columns=new ArrayList<>();plan.path("orderedColumns").forEach(columns::add);
        require(!columns.isEmpty()&&columns.size()<=256,"SCHEMA_BINDING");
        for(var col:columns)require(col.path("attribute").asText().matches("[A-Za-z][A-Za-z0-9_]{0,127}") && col.path("header").equals(col.path("attribute")),"SCHEMA_BINDING");
        var limits=plan.path("limits");cellLimit=limits.path("maxCellBytes").asInt();rowLimit=limits.path("maxRows").asInt();byteLimit=limits.path("maxBytes").asLong();
        require(cellLimit>0&&cellLimit<=32767&&rowLimit>0&&rowLimit<=10000000&&byteLimit>0&&byteLimit<=268435456,"PLAN_LIMIT");
        String mode=plan.path("mode").asText();require(Set.of("append","replace").contains(mode),"PLAN_BINDING");append="append".equals(mode);
        var base=plan.path("baseSnapshot");
        if(append){fields(base,Set.of("versionId","csvObjectKey","csvSha256","csvSize","dataSha256","rowCount"));
            require(uuid(base,"versionId").equals(uuid(plan,"baseVersionId"))&&base.path("csvObjectKey").asText().matches("downloads/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}/data\\.csv"),"PLAN_TARGET");
            require(base.path("dataSha256").asText().matches("[0-9a-f]{64}")&&base.path("rowCount").asLong()>0,"PLAN_BINDING");}
        else require(base.isNull(),"PLAN_BINDING");
        var input=plan.path("input");fields(input,Set.of("size","sha256","privateSpoolReference"));
        require(input.path("size").isIntegralNumber()&&input.path("sha256").asText().matches("[0-9a-f]{64}"),"PLAN_BINDING");
        require(input.path("privateSpoolReference").asText().equals("uploads/"+uuid(plan,"submissionId")+"/input.csv"),"PLAN_TARGET");
        var ch=plan.path("clickhouse");fields(ch,Set.of("candidateDatabase","candidateTable","publicationName"));
        require("di_data".equals(ch.path("candidateDatabase").asText())&&("v_"+hex(plan,"reservedVersionId")+"_"+hex(plan,"executionId")).equals(ch.path("candidateTable").asText())&&("ds_"+hex(plan,"datasetId")+"_i_"+hex(plan,"issueId")+"_current").equals(ch.path("publicationName").asText()),"PLAN_TARGET");
        var outputs=new HashSet<String>();var ids=new HashSet<String>();
        for(var out:plan.path("outputs")){
            fields(out,Set.of("distributionId","format","objectKey","fileName","mediaType"));String id=uuid(out,"distributionId"),format=out.path("format").asText();
            require(Set.of("csv","xlsx","parquet").contains(format)&&outputs.add(format)&&ids.add(id)&&("data."+format).equals(out.path("fileName").asText())&&("downloads/"+id+"/data."+format).equals(out.path("objectKey").asText())&&media(format).equals(out.path("mediaType").asText()),"PLAN_TARGET");
        }
        require(outputs.size()==3,"PLAN_TARGET");
    }
    private void verifyModels()throws IOException{
        var metadata=definition.path("compiledModel");String imd=metadata.path("relativePath").asText();
        require(imd.matches("contracts/compiled/[a-z][a-z0-9_-]*\\.imd")&&"5.6.9".equals(metadata.path("compilerVersion").asText())&&sha(bundle.resolve(imd),2097152).equals(metadata.path("sha256").asText()),"MODEL_HASH");
        var actual=new ArrayList<Map<String,String>>();var names=new HashSet<String>();
        for(var m:plan.path("modelFiles")){
            String rel=m.path("relativePath").asText();
            require(rel.matches("models/[A-Za-z][A-Za-z0-9_]*\\.ili")&&names.add(rel),"MODEL_TARGET");
            String checksum=sha(bundle.resolve(rel),2097152);require(checksum.equals(m.path("sha256").asText()),"MODEL_HASH");
            actual.add(Map.of("relativePath",rel,"sha256",checksum));
        }
        require(!actual.isEmpty()&&actual.size()<=32&&names.contains("models/"+definition.path("modelName").asText()+".ili"),"MODEL_HASH");
        require(sha(JSON.writeValueAsBytes(Map.of("schemaVersion",1,"models",actual))).equals(plan.path("modelSetSha256").asText()),"MODEL_HASH");
    }
    void verifyFile(String name,JsonNode evidence,String sizeField,String hashField,long limit)throws IOException{
        var path=run.resolve(name);long size=evidence.path(sizeField).asLong();
        require(size>0&&size<=limit&&Files.isRegularFile(path,LinkOption.NOFOLLOW_LINKS)&&Files.size(path)==size&&sha(path,limit).equals(evidence.path(hashField).asText()),"INPUT_MISMATCH");
    }
    private static String media(String format){return switch(format){
        case "csv" -> "text/csv; charset=utf-8";
        case "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
        case "parquet" -> "application/vnd.apache.parquet";
        default -> throw new Invalid("PLAN_TARGET",0,null);
    };}
    private static String canonical(JsonNode value)throws IOException{
        if(value.isObject()){
            var keys=new TreeSet<String>();value.fieldNames().forEachRemaining(keys::add);
            var join=new StringJoiner(",","{","}");
            for(String key:keys)join.add(JSON.writeValueAsString(key)+":"+canonical(value.get(key)));
            return join.toString();
        }
        if(value.isArray()){var join=new StringJoiner(",","[","]");for(var v:value)join.add(canonical(v));return join.toString();}
        if(value.isFloatingPointNumber())return value.decimalValue().stripTrailingZeros().toPlainString();
        return JSON.writeValueAsString(value);
    }
    static void fields(JsonNode n,Set<String> expected){var seen=new HashSet<String>();n.fieldNames().forEachRemaining(seen::add);require(n.isObject()&&seen.equals(expected),"PLAN_SCHEMA");}
    static JsonNode json(Path path,int limit)throws IOException{
        require(Files.isRegularFile(path,LinkOption.NOFOLLOW_LINKS),"MISSING_FILE");
        try(var input=Files.newInputStream(path,LinkOption.NOFOLLOW_LINKS)){byte[] bytes=input.readNBytes(limit+1);require(bytes.length<=limit,"JSON_LIMIT");return JSON.readTree(bytes);}
    }
    static String uuid(JsonNode node,String name){String v=node.path(name).asText();require(v.matches("[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}")&&UUID.fromString(v).toString().equals(v),"PLAN_BINDING");return v;}
    static String hex(JsonNode node,String name){return uuid(node,name).replace("-","");}
    static MessageDigest digest(){try{return MessageDigest.getInstance("SHA-256");}catch(NoSuchAlgorithmException e){throw new IllegalStateException(e);}}
    static String sha(byte[] data){return HexFormat.of().formatHex(digest().digest(data));}
    static String sha(Path path,long limit)throws IOException{
        require(Files.isRegularFile(path,LinkOption.NOFOLLOW_LINKS)&&Files.size(path)<=limit,"FILE_LIMIT");var digest=digest();
        try(var in=Files.newInputStream(path,LinkOption.NOFOLLOW_LINKS)){byte[] b=new byte[65536];long count=0;for(int n;(n=in.read(b))>0;){count+=n;require(count<=limit,"FILE_LIMIT");digest.update(b,0,n);}}
        return HexFormat.of().formatHex(digest.digest());
    }
    static void require(boolean ok,String code){if(!ok)throw new Invalid(code,0,null);}
    static final class Invalid extends RuntimeException{
        final String code,attribute;final long row;
        Invalid(String code,long row,String attribute){super(code);this.code=code;this.row=row;this.attribute=attribute;}
    }
}
