<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    xmlns:dcat="http://www.w3.org/ns/dcat#" xmlns:dct="http://purl.org/dc/terms/"
    xmlns:foaf="http://xmlns.com/foaf/0.1/" xmlns:vcard="http://www.w3.org/2006/vcard/ns#"
    xmlns:schema="http://schema.org/" exclude-result-prefixes="#all">
  <xsl:output method="text" encoding="UTF-8"/>
  <!-- Gezielte Prüfung unseres Exportvertrags, kein allgemeiner RDF-Validator.
       Der unabhängige RDF-Parser gehört in die Tests. Hier bleibt der produktive
       Ablauf offline, ohne Auflösung von Vokabularen oder weiteren Bibliotheken. -->
  <xsl:template match="/">
    <xsl:variable name="catalog" select="rdf:RDF/dcat:Catalog"/>
    <xsl:variable name="datasets" select="rdf:RDF/dcat:Dataset"/>
    <xsl:variable name="distributions" select="$datasets/dcat:distribution/dcat:Distribution"/>
    <xsl:if test="count($catalog)!=1 or count(rdf:RDF)!=1 or
        exists(rdf:RDF/*[not(self::dcat:Catalog or self::dcat:Dataset or self::foaf:Organization)])">
      <xsl:message terminate="yes">RDF-Export: Genau ein Katalog und die festgelegten RDF-Klassen werden erwartet.</xsl:message>
    </xsl:if>
    <xsl:if test="count($catalog/dcat:dataset)!=count($datasets) or
        count(distinct-values($catalog/dcat:dataset/@rdf:resource))!=count($datasets) or
        exists($catalog/dcat:dataset[not(@rdf:resource=$datasets/@rdf:about)])">
      <xsl:message terminate="yes">RDF-Export: Die Katalogverweise stimmen nicht mit den Datensätzen überein.</xsl:message>
    </xsl:if>
    <xsl:if test="count(distinct-values($datasets/dct:identifier))!=count($datasets)">
      <xsl:message terminate="yes">RDF-Export: Doppelte Exportkennung nach Ersetzung der Punkte durch Bindestriche.</xsl:message>
    </xsl:if>
    <xsl:if test="count(distinct-values(($catalog/@rdf:about,$datasets/@rdf:about,$distributions/@rdf:about))) != count(($catalog,$datasets,$distributions))">
      <xsl:message terminate="yes">RDF-Export: Katalog-, Datensatz- und Distributions-URIs müssen eindeutig sein.</xsl:message>
    </xsl:if>
    <xsl:for-each select="$catalog | $datasets">
      <xsl:if test="count(dct:title)!=1 or not(dct:title[normalize-space()]) or
          count(dct:description)!=1 or not(dct:description[normalize-space()]) or
          count(dct:publisher)!=1 or not(dct:publisher/@rdf:resource=/rdf:RDF/foaf:Organization/@rdf:about) or
          count(dct:language)!=1">
        <xsl:message terminate="yes">RDF-Export: Titel, Beschreibung, Sprache oder Herausgeber fehlen bei <xsl:value-of select="@rdf:about"/>.</xsl:message>
      </xsl:if>
    </xsl:for-each>
    <xsl:for-each select="$datasets">
      <xsl:if test="count(dct:identifier)!=1 or not(matches(dct:identifier,'^[A-Za-z0-9_-]+@kanton_solothurn$'))">
        <xsl:message terminate="yes">RDF-Export: Unzulässige Exportkennung «<xsl:value-of select="dct:identifier"/>». Erlaubt sind Buchstaben A–Z/a–z, Ziffern, Bindestriche und Unterstriche vor @kanton_solothurn.</xsl:message>
      </xsl:if>
      <xsl:if test="count(dcat:contactPoint/vcard:Organization)!=1 or
          not(dcat:contactPoint/vcard:Organization/vcard:fn[normalize-space()]) or
          count(dcat:contactPoint/vcard:Organization/vcard:hasEmail)!=1 or
          not(matches(string(dcat:contactPoint/vcard:Organization/vcard:hasEmail/@rdf:resource),'^mailto:[^\s@]+@[^\s@]+$')) or
          count(dct:creator/foaf:Organization)!=1 or not(dct:creator/foaf:Organization/foaf:name[normalize-space()]) or
          not(dcat:distribution) or exists(dcat:distribution[count(dcat:Distribution)!=1])">
        <xsl:message terminate="yes">RDF-Export: Kontakt, Ersteller oder Distribution fehlen bei <xsl:value-of select="dct:identifier"/>.</xsl:message>
      </xsl:if>
    </xsl:for-each>
    <xsl:for-each select="$datasets | $distributions">
      <xsl:if test="count(dct:issued)!=1 or not(dct:issued castable as xs:date) or
          count(dct:modified)!=1 or not(dct:modified castable as xs:date)">
        <xsl:message terminate="yes">RDF-Export: Gültige Datumswerte issued und modified sind für Datensatz und Distribution erforderlich: <xsl:value-of select="@rdf:about"/>.</xsl:message>
      </xsl:if>
      <xsl:if test="xs:date(dct:issued) gt xs:date(dct:modified)">
        <xsl:message terminate="yes">RDF-Export: issued liegt nach modified bei <xsl:value-of select="@rdf:about"/>.</xsl:message>
      </xsl:if>
    </xsl:for-each>
    <xsl:for-each select="$distributions">
      <xsl:if test="count(dcat:accessURL)!=1 or count(dcat:downloadURL)!=1 or count(dct:license)!=1 or
          dct:issued!=../../dct:issued or dct:modified!=../../dct:modified or
          (exists(dct:format) != exists(dcat:mediaType))">
        <xsl:message terminate="yes">RDF-Export: Unvollständige Distribution oder abweichende Lieferdatumswerte bei <xsl:value-of select="@rdf:about"/>.</xsl:message>
      </xsl:if>
    </xsl:for-each>
    <xsl:for-each select="//dct:PeriodOfTime">
      <xsl:if test="not(schema:startDate or schema:endDate) or
          exists(*[not(. castable as xs:date)])">
        <xsl:message terminate="yes">RDF-Export: Ungültige zeitliche Abdeckung.</xsl:message>
      </xsl:if>
      <xsl:if test="schema:startDate and schema:endDate and xs:date(schema:startDate) gt xs:date(schema:endDate)">
        <xsl:message terminate="yes">RDF-Export: Beginn der zeitlichen Abdeckung liegt nach dem Ende.</xsl:message>
      </xsl:if>
    </xsl:for-each>
    <xsl:if test="exists((//dct:title | //dct:description | //foaf:name | //vcard:fn | //dcat:keyword)[not(@xml:lang='de')]) or
        exists((//dct:issued | //dct:modified | //schema:startDate | //schema:endDate)[not(@rdf:datatype='http://www.w3.org/2001/XMLSchema#date')])">
      <xsl:message terminate="yes">RDF-Export: Texte benötigen die Sprache de, Datumswerte den Datentyp xsd:date.</xsl:message>
    </xsl:if>
    <xsl:for-each select="//@rdf:about | //@rdf:resource">
      <xsl:if test="not(matches(.,'^(https?://[^\s/]+[^\s]*|mailto:[^\s@]+@[^\s@]+)$'))">
        <xsl:message terminate="yes">RDF-Export: Leere oder ungültige Ressourcenadresse bei <xsl:value-of select="name(..)"/>.</xsl:message>
      </xsl:if>
    </xsl:for-each>
    <!-- Null Datensätze ist der vereinbarte Lösch-/Erststand. Das heutige
         Harvesterprofil verlangt normalerweise mindestens einen Datensatz;
         dessen Löschverhalten muss vor dem produktiven Anschluss geprüft werden. -->
    <xsl:text>{"datasetCount":</xsl:text><xsl:value-of select="count($datasets)"/><xsl:text>}</xsl:text>
  </xsl:template>
</xsl:stylesheet>
