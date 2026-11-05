package ch.so.agi.dateninfrastruktur.ingest;

import com.fasterxml.jackson.databind.JsonNode;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.zip.*;
import javax.xml.stream.*;

/** Streaming worksheet. Numeric values use their exact lexical form; text never becomes a formula. */
final class Xlsx implements AutoCloseable {
    private static final String MAIN="http://schemas.openxmlformats.org/spreadsheetml/2006/main";
    private static final String REL="http://schemas.openxmlformats.org/officeDocument/2006/relationships";
    private static final String PKG="http://schemas.openxmlformats.org/package/2006/relationships";
    private final ZipOutputStream zip;
    private final XMLStreamWriter xml;
    private final List<JsonNode> columns;
    private long row;
    Xlsx(Path path,List<JsonNode> columns)throws IOException,XMLStreamException{
        this.columns=columns;
        zip=new ZipOutputStream(new BufferedOutputStream(Files.newOutputStream(path,StandardOpenOption.CREATE_NEW)));
        entry("[Content_Types].xml","<Types xmlns='http://schemas.openxmlformats.org/package/2006/content-types'><Default Extension='rels' ContentType='application/vnd.openxmlformats-package.relationships+xml'/><Default Extension='xml' ContentType='application/xml'/><Override PartName='/xl/workbook.xml' ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml'/><Override PartName='/xl/worksheets/sheet1.xml' ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml'/><Override PartName='/xl/styles.xml' ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml'/></Types>");
        entry("_rels/.rels","<Relationships xmlns='"+PKG+"'><Relationship Id='rId1' Type='"+REL+"/officeDocument' Target='xl/workbook.xml'/></Relationships>");
        entry("xl/workbook.xml","<workbook xmlns='"+MAIN+"' xmlns:r='"+REL+"'><sheets><sheet name='Daten' sheetId='1' r:id='rId1'/></sheets></workbook>");
        entry("xl/_rels/workbook.xml.rels","<Relationships xmlns='"+PKG+"'><Relationship Id='rId1' Type='"+REL+"/worksheet' Target='worksheets/sheet1.xml'/><Relationship Id='rId2' Type='"+REL+"/styles' Target='styles.xml'/></Relationships>");
        entry("xl/styles.xml","<styleSheet xmlns='"+MAIN+"'><fonts count='1'><font><sz val='11'/><name val='Calibri'/></font></fonts><fills count='2'><fill><patternFill patternType='none'/></fill><fill><patternFill patternType='gray125'/></fill></fills><borders count='1'><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count='1'><xf numFmtId='0' fontId='0' fillId='0' borderId='0'/></cellStyleXfs><cellXfs count='2'><xf numFmtId='0' fontId='0' fillId='0' borderId='0' xfId='0'/><xf numFmtId='14' fontId='0' fillId='0' borderId='0' xfId='0' applyNumberFormat='1'/></cellXfs><cellStyles count='1'><cellStyle name='Normal' xfId='0' builtinId='0'/></cellStyles></styleSheet>");
        zip.putNextEntry(new ZipEntry("xl/worksheets/sheet1.xml"));
        xml=XMLOutputFactory.newFactory().createXMLStreamWriter(zip,StandardCharsets.UTF_8.name());
        xml.writeStartDocument("UTF-8","1.0");xml.writeStartElement("worksheet");xml.writeDefaultNamespace(MAIN);xml.writeStartElement("sheetData");
        start();
        for(int i=0;i<columns.size();i++)cell(i,"text",columns.get(i).path("header").asText());
        xml.writeEndElement();
    }
    private void entry(String name,String text)throws IOException{zip.putNextEntry(new ZipEntry(name));zip.write(text.getBytes(StandardCharsets.UTF_8));zip.closeEntry();}
    private void start()throws XMLStreamException{
        if(++row>1048576)throw CsvRows.invalid("XLSX_ROW_LIMIT",row,null);
        xml.writeStartElement("row");xml.writeAttribute("r",Long.toString(row));
    }
    void row(JsonNode values)throws XMLStreamException{
        start();for(int i=0;i<values.size();i++)if(!values.get(i).isNull())cell(i,columns.get(i).path("type").asText(),values.get(i).asText());xml.writeEndElement();
    }
    private void cell(int index,String type,String value)throws XMLStreamException{
        xml.writeStartElement("c");xml.writeAttribute("r",coordinate(index)+row);
        switch(type){
            case "integer","decimal" -> scalar("n",value);
            case "boolean" -> scalar("b","true".equals(value)?"1":"0");
            case "date" -> {
                xml.writeAttribute("s","1");LocalDate date=LocalDate.parse(value);
                long serial=ChronoUnit.DAYS.between(LocalDate.of(1899,12,31),date)+(date.isBefore(LocalDate.of(1900,3,1))?0:1);
                scalar("n",Long.toString(serial));
            }
            // UTC is explicit and millisecond-exact; XLSX numbers have no timezone.
            default -> {
                if(value.length()>32767)throw CsvRows.invalid("XLSX_CELL_LIMIT",row,null);
                xml.writeAttribute("t","inlineStr");xml.writeStartElement("is");xml.writeStartElement("t");
                xml.writeAttribute("xml","http://www.w3.org/XML/1998/namespace","space","preserve");xml.writeCharacters(value);xml.writeEndElement();xml.writeEndElement();
            }
        }
        xml.writeEndElement();
    }
    private void scalar(String type,String value)throws XMLStreamException{xml.writeAttribute("t",type);xml.writeStartElement("v");xml.writeCharacters(value);xml.writeEndElement();}
    private static String coordinate(int i){var b=new StringBuilder();for(int n=i+1;n>0;n=(n-1)/26)b.append((char)('A'+(n-1)%26));return b.reverse().toString();}
    @Override public void close()throws IOException,XMLStreamException{try{xml.writeEndElement();xml.writeEndElement();xml.writeEndDocument();xml.flush();zip.closeEntry();}finally{zip.close();}}
}
