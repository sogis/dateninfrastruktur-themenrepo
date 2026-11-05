# Themenrepo der Dateninfrastruktur

`contracts/` enthält die versionierten CSV-Lieferverträge und die zugehörigen
Schemas und Metadaten. `models/` enthält die gepinnten INTERLIS-Modelle. Der
gemeinsame Compose-Stack baut diese Quellen in das Jenkins-Runnerbundle ein.
Der Admin-Datenbankkatalog bestimmt, für welche Datensätze ein Vertrag gilt
und wer liefern darf. Neue Aufträge verwenden die Oberfläche `/anlieferung`.

`runner/` enthält den festen GRETL-Einstieg `ingestCsv`, die
Snapshotverarbeitung und die Exporte. Der Runner liest ausschliesslich einen
servergebundenen Plan. `fixtures/csv-g4/` enthält synthetische Prüfdaten zu den
zwei bestehenden Modellen und dem separaten technischen Typvertrag.

Der bestehende eigenständige ClickHouse-Lader und seine Daten bleiben erhalten.
Die ältere Organisations- und Publikationsdokumentation unter
[docs/biblios](docs/biblios/index.adoc) beschreibt die damalige Installation.
Sie ist keine Anleitung zur CSV-Anlieferung und ihre Benutzer- und
Jobbeschreibungen werden nicht zur Laufzeit eingelesen.

Die Buildkoordinaten für GRETL liegen unter `shared/gradle/`. Für MA-G verwendet
das Jenkins-Image das in MA-G0 identifizierte Offline-Bundle mit geprüften
JAR-Hashes.
