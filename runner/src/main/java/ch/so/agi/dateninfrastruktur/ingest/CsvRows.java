package ch.so.agi.dateninfrastruktur.ingest;

import com.fasterxml.jackson.databind.JsonNode;
import java.io.*;
import java.math.*;
import java.nio.charset.*;
import java.nio.file.*;
import java.time.*;
import java.time.format.*;
import java.util.*;
import java.util.regex.*;

/** Explicit UTF-8/LF/quote dialect; one bounded row in memory. */
final class CsvRows {
    private static final Pattern ENUM=Pattern.compile("'([A-Za-z][A-Za-z0-9_]*)'=[0-9]+");
    private static final Pattern SCALE=Pattern.compile("Decimal\\([0-9]+,([0-9]+)\\)");
    private static final DateTimeFormatter UTC=DateTimeFormatter.ofPattern("uuuu-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC);
    private final PlanReader plan;
    CsvRows(PlanReader plan){this.plan=plan;}
    interface RowSink {void row(long index,List<String> cells)throws Exception;}
    long read(Path file,RowSink sink)throws Exception{
        var decoder=StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT);
        try(var reader=new PushbackReader(new BufferedReader(new InputStreamReader(Files.newInputStream(file,LinkOption.NOFOLLOW_LINKS),decoder)),1)){
            var expected=plan.columns.stream().map(c->c.path("header").asText()).toList();
            if(!expected.equals(row(reader,1)))throw invalid("HEADER",1,null);
            long index=0;
            for(List<String> values;(values=row(reader,index+2))!=null;){
                if(++index>plan.rowLimit)throw invalid("ROW_LIMIT",index+1,null);
                if(values.size()!=expected.size())throw invalid("COLUMN_COUNT",index+1,null);
                var normalized=new ArrayList<String>(values.size());
                for(int i=0;i<values.size();i++)normalized.add(value(values.get(i),plan.columns.get(i),index+1));
                sink.row(index,normalized);
            }
            return index;
        }catch(CharacterCodingException e){throw invalid("UTF8",0,null);}
    }
    private List<String> row(PushbackReader in,long number)throws IOException{
        List<String> values=new ArrayList<>(plan.columns.size());var cell=new StringBuilder();
        boolean quoted=false,closed=false,start=true,seen=false;
        while(true){
            int b=in.read();
            if(b==-1){if(quoted)throw invalid("QUOTE",number,null);if(!seen)return null;add(values,cell,number);return values;}
            seen=true;char ch=(char)b;
            if(ch=='\r'||ch==0||ch=='\ufeff'||(ch<32&&ch!='\n'&&ch!='\t')||ch=='\ufffe'||ch=='\uffff')throw invalid("DIALECT",number,null);
            if(quoted){
                if(ch=='"'){
                    int next=in.read();
                    if(next=='"')cell.append('"');
                    else{quoted=false;closed=true;if(next>=0)in.unread(next);}
                }else cell.append(ch);
            }else if(ch==plan.separator||ch=='\n'){
                add(values,cell,number);if(ch=='\n')return values;
                cell.setLength(0);start=true;closed=false;
            }else if(closed)throw invalid("QUOTE",number,null);
            else if(ch=='"'){
                if(!start)throw invalid("QUOTE",number,null);
                quoted=true;start=false;
            }else{start=false;cell.append(ch);}
            if(cell.length()>plan.cellLimit)throw invalid("CELL_LIMIT",number,null);
        }
    }
    private void add(List<String> values,StringBuilder cell,long row){
        if(values.size()>=plan.columns.size())throw invalid("COLUMN_COUNT",row,null);
        String value=cell.toString();if(value.getBytes(StandardCharsets.UTF_8).length>plan.cellLimit)throw invalid("CELL_LIMIT",row,plan.columns.get(values.size()).path("header").asText());
        values.add(value);
    }
    private String value(String raw,JsonNode col,long row){
        String attribute=col.path("attribute").asText(),type=col.path("type").asText();
        if(raw.isEmpty()){
            if(col.path("mandatory").asBoolean())throw invalid("MANDATORY",row,attribute);
            return null;
        }
        try{return switch(type){
            case "text" -> {if(raw.indexOf('\n')>=0)throw new IllegalArgumentException();yield raw;}
            case "mtext" -> raw;
            case "boolean" -> {if(!Set.of("true","false").contains(raw))throw new IllegalArgumentException();yield raw;}
            case "enum" -> {var match=ENUM.matcher(col.path("clickhouseType").asText());boolean known=false;while(match.find())if(raw.equals(match.group(1)))known=true;if(!known)throw new IllegalArgumentException();yield raw;}
            case "integer" -> {
                if(!raw.matches("-?(0|[1-9][0-9]{0,9})"))throw new IllegalArgumentException();
                var number=BigDecimal.valueOf(Integer.parseInt(raw));within(number,col);yield number.toPlainString();
            }
            case "decimal" -> {
                if(!raw.matches("-?(0|[1-9][0-9]{0,17})(\\.[0-9]{1,9})?"))throw new IllegalArgumentException();
                var spec=SCALE.matcher(col.path("clickhouseType").asText());if(!spec.find())throw new IllegalArgumentException();
                var number=new BigDecimal(raw);within(number,col);yield number.setScale(Integer.parseInt(spec.group(1)),RoundingMode.UNNECESSARY).toPlainString();
            }
            case "date" -> {
                if(!raw.matches("[0-9]{4}-[0-9]{2}-[0-9]{2}"))throw new IllegalArgumentException();
                var date=LocalDate.parse(raw);year(date.getYear());yield date.toString();
            }
            case "timestamp" -> {
                if(!raw.matches("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,3})?(Z|[+-][0-9]{2}:[0-9]{2})"))throw new IllegalArgumentException();
                var instant=OffsetDateTime.parse(raw).toInstant();year(instant.atOffset(ZoneOffset.UTC).getYear());yield UTC.format(instant);
            }
            default -> throw new IllegalArgumentException();
        };}catch(RuntimeException e){throw invalid("INVALID_TYPE",row,attribute);}
    }
    private static void within(BigDecimal value,JsonNode col){if(value.compareTo(col.path("minimum").decimalValue())<0||value.compareTo(col.path("maximum").decimalValue())>0)throw new IllegalArgumentException();}
    private static void year(int y){if(y<1900||y>2299)throw new IllegalArgumentException();}
    void write(Writer out,List<String> values)throws IOException{
        for(int i=0;i<values.size();i++){
            if(i>0)out.write(plan.separator);
            String v=values.get(i);if(v==null)continue;
            if(v.indexOf(plan.separator)>=0||v.indexOf('"')>=0||v.indexOf('\n')>=0){out.write('"');out.write(v.replace("\"","\"\""));out.write('"');}
            else out.write(v);
        }
        out.write('\n');
    }
    static PlanReader.Invalid invalid(String code,long row,String attribute){return new PlanReader.Invalid(code,row,attribute);}
}
