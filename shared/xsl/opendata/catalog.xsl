<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="2.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:ili="http://www.interlis.ch/xtf/2.4/INTERLIS"
    xmlns:p="http://www.interlis.ch/xtf/2.4/SO_AGI_DataCatalog_PublishedCatalog_20260602"
    xmlns:b="http://www.interlis.ch/xtf/2.4/SO_AGI_DataCatalog_Base_20260529"
    xmlns:empty="urn:so:datenportal:opendata:empty"
    xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    xmlns:dcat="http://www.w3.org/ns/dcat#" xmlns:dct="http://purl.org/dc/terms/"
    xmlns:foaf="http://xmlns.com/foaf/0.1/" xmlns:vcard="http://www.w3.org/2006/vcard/ns#"
    xmlns:schema="http://schema.org/" exclude-result-prefixes="ili p b empty">
  <xsl:output method="xml" encoding="UTF-8" indent="yes"/>
  <!-- Vertrag des heute implementierten Importprofils, bewusst ohne V3-Serien.
       Alle kantonalen Konstanten stehen hier. Fachliche Serienvererbung erfolgt
       vor dem XTF-Export in SQL, damit Portal und RDF dieselben Angaben erhalten. -->
  <xsl:variable name="catalogUri" select="'https://data.so.ch/catalog/opendata'"/>
  <xsl:variable name="catalogTitle" select="'Datenportal Kanton Solothurn'"/>
  <xsl:variable name="catalogDescription" select="'Datensätze und Datenserien des Kantons Solothurn'"/>
  <xsl:variable name="homepage" select="'https://data.so.ch/'"/>
  <xsl:variable name="publisherUri" select="'https://so.ch/'"/>
  <xsl:variable name="publisherName" select="'Kanton Solothurn'"/>
  <xsl:variable name="organization" select="'kanton_solothurn'"/>
  <xsl:variable name="license" select="'http://dcat-ap.ch/vocabulary/licenses/terms_open'"/>
  <xsl:variable name="language" select="'http://publications.europa.eu/resource/authority/language/DEU'"/>
  <xsl:variable name="catalog" select="/ili:transfer/ili:datasection/p:Publication/p:Catalog"/>
  <xsl:variable name="datasets" select="$catalog/p:datasets/p:Dataset[p:publicationStatus='published'] |
      $catalog/p:datasetSeries/p:DatasetSeries[p:publicationStatus='published']/p:issues/p:DatasetIssue[p:publicationStatus='published']"/>

  <xsl:template match="/">
    <xsl:if test="not(count($catalog)=1 or /empty:emptyCatalog)">
      <xsl:message terminate="yes">RDF-Export: Erwartet wird ein PublishedCatalog der Modellversion 20260602 oder der ausdrückliche Leerstand.</xsl:message>
    </xsl:if>
    <rdf:RDF>
      <dcat:Catalog rdf:about="{$catalogUri}">
        <dct:title xml:lang="de"><xsl:value-of select="$catalogTitle"/></dct:title>
        <dct:description xml:lang="de"><xsl:value-of select="$catalogDescription"/></dct:description>
        <dct:publisher rdf:resource="{$publisherUri}"/>
        <foaf:homepage rdf:resource="{$homepage}"/>
        <dct:language rdf:resource="{$language}"/>
        <xsl:for-each select="$datasets">
          <xsl:sort select="p:identifier"/>
          <dcat:dataset rdf:resource="{p:resourceUri}"/>
        </xsl:for-each>
      </dcat:Catalog>
      <foaf:Organization rdf:about="{$publisherUri}">
        <foaf:name xml:lang="de"><xsl:value-of select="$publisherName"/></foaf:name>
      </foaf:Organization>
      <xsl:apply-templates select="$datasets"><xsl:sort select="p:identifier"/></xsl:apply-templates>
    </rdf:RDF>
  </xsl:template>

  <xsl:template match="p:Dataset | p:DatasetIssue">
    <dcat:Dataset rdf:about="{p:resourceUri}">
      <dct:identifier><xsl:value-of select="concat(translate(p:identifier,'.','-'),'@',$organization)"/></dct:identifier>
      <dct:title xml:lang="de"><xsl:value-of select="p:title"/></dct:title>
      <dct:description xml:lang="de"><xsl:value-of select="p:description"/></dct:description>
      <dct:publisher rdf:resource="{$publisherUri}"/>
      <dct:creator>
        <foaf:Organization rdf:about="{p:creator/p:Office/p:officeUri}">
          <foaf:name xml:lang="de"><xsl:value-of select="p:creator/p:Office/p:name"/></foaf:name>
        </foaf:Organization>
      </dct:creator>
      <dcat:contactPoint>
        <vcard:Organization>
          <!-- Der Name ist im INTERLIS-Kontakt optional. Die Amtsstelle benennt
               den Kontakt auch dann sinnvoll; die Mailadresse wird nie erfunden. -->
          <vcard:fn xml:lang="de"><xsl:value-of select="(p:contactPoint/b:ContactPoint/b:name[normalize-space()], p:contactPoint/b:ContactPoint/b:organizationUnit[normalize-space()], p:creator/p:Office/p:name)[1]"/></vcard:fn>
          <vcard:hasEmail rdf:resource="{p:contactPoint/b:ContactPoint/b:email}"/>
          <xsl:if test="p:contactPoint/b:ContactPoint/b:url[normalize-space()]"><vcard:hasURL rdf:resource="{p:contactPoint/b:ContactPoint/b:url}"/></xsl:if>
        </vcard:Organization>
      </dcat:contactPoint>
      <xsl:for-each select="p:themes/p:ThemeAssignment/p:themeUri"><xsl:sort select="."/>
        <dcat:theme rdf:resource="{.}"/>
      </xsl:for-each>
      <xsl:for-each select="p:keywords[normalize-space()]"><xsl:sort select="."/>
        <dcat:keyword xml:lang="de"><xsl:value-of select="."/></dcat:keyword>
      </xsl:for-each>
      <xsl:if test="p:landingPage[normalize-space()]"><dcat:landingPage rdf:resource="{p:landingPage}"/></xsl:if>
      <dct:language rdf:resource="{$language}"/>
      <xsl:call-template name="dates"/>
      <xsl:if test="p:accrualPeriodicity/p:AccrualPeriodicity/p:frequencyUri[normalize-space()]"><dct:accrualPeriodicity rdf:resource="{p:accrualPeriodicity/p:AccrualPeriodicity/p:frequencyUri}"/></xsl:if>
      <xsl:for-each select="p:temporalCoverage/b:TemporalCoverage">
        <dct:temporal><dct:PeriodOfTime>
          <xsl:if test="b:startDate or b:referenceDate"><schema:startDate rdf:datatype="http://www.w3.org/2001/XMLSchema#date"><xsl:value-of select="(b:referenceDate,b:startDate)[1]"/></schema:startDate></xsl:if>
          <xsl:if test="b:endDate or b:referenceDate"><schema:endDate rdf:datatype="http://www.w3.org/2001/XMLSchema#date"><xsl:value-of select="(b:referenceDate,b:endDate)[1]"/></schema:endDate></xsl:if>
        </dct:PeriodOfTime></dct:temporal>
      </xsl:for-each>
      <xsl:for-each select="p:distributions/p:Distribution">
        <xsl:sort select="p:distributionUri"/>
        <dcat:distribution><dcat:Distribution rdf:about="{p:distributionUri}">
          <dcat:accessURL rdf:resource="{p:accessURL}"/>
          <dcat:downloadURL rdf:resource="{p:downloadURL}"/>
          <dct:title xml:lang="de"><xsl:value-of select="../../p:title"/></dct:title>
          <dct:license rdf:resource="{$license}"/>
          <dct:language rdf:resource="{$language}"/>
          <xsl:for-each select="../.."><xsl:call-template name="dates"/></xsl:for-each>
          <!-- «other» bezeichnet kein bekanntes Format. Die Links bleiben erhalten,
               ohne MIME-Typ oder Vokabularwert aus der Dateiendung zu erraten. -->
          <xsl:if test="p:format=('csv','xlsx','parquet')">
            <dct:format rdf:resource="{concat('http://publications.europa.eu/resource/authority/file-type/',upper-case(p:format))}"/>
            <dcat:mediaType rdf:resource="{concat('https://www.iana.org/assignments/media-types/', if (p:format='csv') then 'text/csv' else if (p:format='xlsx') then 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' else 'application/vnd.apache.parquet')}"/>
          </xsl:if>
        </dcat:Distribution></dcat:distribution>
      </xsl:for-each>
    </dcat:Dataset>
  </xsl:template>
  <xsl:template name="dates">
    <!-- issued wird auch für jede Distribution verlangt. Fehlende Werte bleiben
         sichtbar leer, damit der nachfolgende Prüfschritt verständlich abbricht. -->
    <dct:issued rdf:datatype="http://www.w3.org/2001/XMLSchema#date"><xsl:value-of select="p:issued"/></dct:issued>
    <dct:modified rdf:datatype="http://www.w3.org/2001/XMLSchema#date"><xsl:value-of select="p:modified"/></dct:modified>
  </xsl:template>
</xsl:stylesheet>
