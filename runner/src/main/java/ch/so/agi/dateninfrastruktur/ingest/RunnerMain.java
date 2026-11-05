package ch.so.agi.dateninfrastruktur.ingest;

import com.fasterxml.jackson.databind.JsonNode;
import java.io.*;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.sql.*;
import java.util.*;

public final class RunnerMain {
    static final long SNAPSHOT_BYTE_LIMIT=1073741824L;
    public static void main(String[] args)throws Exception{
        if(args.length!=3||!Set.of("prepare","export").contains(args[0]))throw new IllegalArgumentException("Fixed runner invocation required");
        var run=Path.of(args[1]);
        try{
            var plan=new PlanReader(run,Path.of(args[2]));
            if("prepare".equals(args[0]))prepare(plan);else export(plan);
        }catch(PlanReader.Invalid e){
            var safe=new LinkedHashMap<String,Object>();safe.put("code",e.code);safe.put("row",e.row);safe.put("attribute",e.attribute);
            PlanReader.JSON.writeValue(run.resolve("validation-error.json").toFile(),safe);
            throw new IllegalStateException("CSV runner rejected the input or plan.");
        }
    }
    private static final class Hash {
        private final MessageDigest digest=PlanReader.digest();
        long rows=0;
        byte[] add(List<String> cells)throws IOException{
            byte[] json=PlanReader.JSON.writeValueAsBytes(cells);digest.update(json);digest.update((byte)'\n');rows++;return json;
        }
        String finish(){return HexFormat.of().formatHex(digest.digest());}
    }
    private static void prepare(PlanReader p)throws Exception{
        var input=p.plan.path("input");p.verifyFile("input.csv",input,"size","sha256",p.byteLimit);
        var base=p.plan.path("baseSnapshot");if(p.append)p.verifyFile("base.csv",base,"csvSize","csvSha256",SNAPSHOT_BYTE_LIMIT);
        PlanReader.require((p.append?base.path("csvSize").asLong():0)+input.path("size").asLong()<=SNAPSHOT_BYTE_LIMIT,"SNAPSHOT_LIMIT");
        Files.createDirectory(p.run.resolve("models"));
        for(var m:p.plan.path("modelFiles")){
            var rel=Path.of(m.path("relativePath").asText());Files.copy(p.bundle.resolve(rel),p.run.resolve("models").resolve(rel.getFileName()));
        }
        var codec=new CsvRows(p);var delta=new Hash();var full=new Hash();var old=new Hash();
        List<String> headers=p.columns.stream().map(c->c.path("attribute").asText()).toList();
        try(var cv=writer(p,"data.csv");var val=writer(p,"snapshot-validation.csv");
            var iv=writer(p,"incoming-validation.csv");var normalized=Files.newOutputStream(p.run.resolve("snapshot.rows"),StandardOpenOption.CREATE_NEW);
            var ch=Files.newOutputStream(p.run.resolve("snapshot.ch.jsonl"),StandardOpenOption.CREATE_NEW)){
            codec.write(cv,headers);codec.write(val,headers);codec.write(iv,headers);
            CsvRows.RowSink merged=(index,row)->{
                if(full.rows>=p.rowLimit)throw CsvRows.invalid("ROW_LIMIT",index+1,null);
                codec.write(cv,row);codec.write(val,validatorValues(p,row));
                normalized.write(full.add(row));normalized.write('\n');
                var typed=new ArrayList<Object>();typed.add(full.rows);
                for(int i=0;i<row.size();i++){
                    String value=row.get(i);String type=p.columns.get(i).path("type").asText();
                    typed.add(value==null?null:switch(type){
                        case "integer" -> Integer.valueOf(value);
                        case "decimal" -> new BigDecimal(value);
                        case "boolean" -> Boolean.valueOf(value);
                        case "timestamp" -> value.substring(0,value.length()-1).replace('T',' ');
                        default -> value;
                    });
                }
                ch.write(PlanReader.JSON.writeValueAsBytes(typed));ch.write('\n');
            };
            if(p.append){
                codec.read(p.run.resolve("base.csv"),(i,row)->{old.add(row);merged.row(i,row);});
                PlanReader.require(old.rows==base.path("rowCount").asLong() && old.finish().equals(base.path("dataSha256").asText()),"BASE_DATA_HASH");
            }
            codec.read(p.run.resolve("input.csv"),(i,row)->{delta.add(row);codec.write(iv,validatorValues(p,row));merged.row(i,row);});
        }
        PlanReader.require(delta.rows>0&&full.rows>0,"EMPTY_SNAPSHOT");
        PlanReader.require(Files.size(p.run.resolve("data.csv"))<=SNAPSHOT_BYTE_LIMIT,"SNAPSHOT_LIMIT");
        PlanReader.JSON.writeValue(p.run.resolve("normalized.json").toFile(),Map.of("incomingRows",delta.rows,"incomingHash",delta.finish(),"snapshotRows",full.rows,"snapshotHash",full.finish()));
    }
    private static List<String> validatorValues(PlanReader p,List<String> row){
        var values=new ArrayList<>(row);
        for(int i=0;i<values.size();i++)if(values.get(i)!=null&&"timestamp".equals(p.columns.get(i).path("type").asText())){
            // INTERLIS.XMLDateTime is a Gregorian value with no offset in its format.
            // Parse the required input offset above; give the validator the normalized UTC wall time.
            var v=values.get(i);values.set(i,v.substring(0,v.length()-1));
        }
        return values;
    }
    private static BufferedWriter writer(PlanReader p,String name)throws IOException{return Files.newBufferedWriter(p.run.resolve(name),StandardCharsets.UTF_8,StandardOpenOption.CREATE_NEW);}
    private static void export(PlanReader p)throws Exception{
        var data=PlanReader.json(p.run.resolve("normalized.json"),8192);
        for(String name:List.of("validateIncomingCsv","validateCompleteSnapshot")){
            var report=PlanReader.json(p.run.resolve(name+".json"),8192);
            PlanReader.fields(report,Set.of("executed","validationOk","errors","validator","modelSetSha256"));
            PlanReader.require(report.path("executed").asBoolean()&&report.path("validationOk").asBoolean()&&report.path("errors").isIntegralNumber()&&report.path("errors").asInt()==0&&"1.15.0".equals(report.path("validator").asText())&&p.plan.path("modelSetSha256").equals(report.path("modelSetSha256")),"VALIDATOR_EVIDENCE");
        }
        try(var connection=DriverManager.getConnection("jdbc:duckdb:"+p.run.resolve("snapshot.duckdb"));var sql=connection.createStatement()){
            sql.execute("SET TimeZone='UTC'");
            sql.execute("SET memory_limit='256MB'");
            sql.execute("SET temp_directory="+literal(p.run.resolve("duckdb-spill").toString()));
            String ddl=String.join(",",p.columns.stream().map(c->id(c)+" "+duckType(c)).toList());
            sql.execute("CREATE TABLE snapshot (_di_ordinal BIGINT NOT NULL,"+ddl+")");
            var names=p.columns.stream().map(RunnerMain::id).toList();
            try(var insert=connection.prepareStatement("INSERT INTO snapshot VALUES ("+"?,".repeat(names.size())+"?)");
                var xlsx=new Xlsx(p.run.resolve("data.xlsx"),p.columns);
                var reader=Files.newBufferedReader(p.run.resolve("snapshot.rows"),StandardCharsets.UTF_8)){
                connection.setAutoCommit(false);
                long count=0;
                for(String line;(line=reader.readLine())!=null;){
                    var values=PlanReader.JSON.readTree(line);PlanReader.require(values.isArray()&&values.size()==names.size(),"SNAPSHOT_ROW");
                    insert.setLong(1,++count);
                    for(int i=0;i<values.size();i++){
                        var v=values.get(i);if(v.isNull())insert.setNull(i+2,Types.VARCHAR);else insert.setString(i+2,v.asText());
                    }
                    insert.addBatch();if(count%1000==0)insert.executeBatch();
                    xlsx.row(values);
                }
                insert.executeBatch();connection.commit();
                PlanReader.require(count==data.path("snapshotRows").asLong(),"SNAPSHOT_COUNT");
            }
            var keys=new ArrayList<String>();p.plan.path("rowKeyDefinition").forEach(k->keys.add(quoteIdentifier(k.asText())));
            if(!keys.isEmpty()){
                try(var duplicate=sql.executeQuery("SELECT 1 FROM snapshot GROUP BY "+String.join(",",keys)+" HAVING count(*)>1 LIMIT 1")){
                    if(duplicate.next())throw CsvRows.invalid("BUSINESS_KEY_DUPLICATE",0,null);
                }
            }
            sql.execute("COPY (SELECT "+String.join(",",names)+" FROM snapshot ORDER BY _di_ordinal) TO "+literal(p.run.resolve("data.parquet").toString())+" (FORMAT PARQUET, COMPRESSION ZSTD)");
        }
        var result=new LinkedHashMap<String,Object>();
        result.put("incoming",validation(p,data,"incoming"));result.put("snapshot",validation(p,data,"snapshot"));
        PlanReader.JSON.writeValue(p.run.resolve("local-evidence.json").toFile(),result);
    }
    private static Map<String,Object> validation(PlanReader p,JsonNode data,String key){
        return Map.of("schemaVersion",1,"definitionSha256",p.plan.path("definitionSha256").asText(),"modelSetSha256",p.plan.path("modelSetSha256").asText(),"validatorVersion","1.15.0","valid",true,"rowCount",data.path(key+"Rows").asLong(),"dataSha256",data.path(key+"Hash").asText());
    }
    private static String duckType(JsonNode column){
        return switch(column.path("type").asText()){
            case "integer" -> "INTEGER";
            case "decimal" -> {
                String type=column.path("clickhouseType").asText().replace("Nullable(","");if(type.endsWith("))"))type=type.substring(0,type.length()-1);
                PlanReader.require(type.matches("Decimal\\([0-9]{1,2},[0-9]\\)"),"PLAN_TYPE");yield type;
            }
            case "boolean" -> "BOOLEAN";
            case "date" -> "DATE";
            case "timestamp" -> "TIMESTAMPTZ";
            case "text","mtext","enum" -> "VARCHAR";
            default -> throw new PlanReader.Invalid("PLAN_TYPE",0,null);
        };
    }
    private static String id(JsonNode c){return quoteIdentifier(c.path("attribute").asText());}
    private static String quoteIdentifier(String s){PlanReader.require(s.matches("[A-Za-z][A-Za-z0-9_]{0,127}"),"PLAN_TYPE");return "\""+s+"\"";}
    private static String literal(String s){return "'"+s.replace("'","''")+"'";}
}
