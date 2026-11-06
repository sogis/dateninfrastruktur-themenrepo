# Themenrepo der Dateninfrastruktur

`contracts/` enthält die versionierten CSV-Lieferverträge mit Schema- und
Modellbezügen. `models/` enthält die gepinnten INTERLIS-Modelle.
Der Admin-Katalog bestimmt, für welche Datensätze ein Vertrag gilt und
wer liefern darf. Ein neuer Vertrag bindet Modellbytes, tatsächliche
Compiler-Ausgabe, Spalten, Typen und Integritätsprüfungen.

`runner/` enthält den GRETL-Einstieg `ingestCsv` für Validierung,
Snapshotbildung und Exporte. Der Runner liest ausschliesslich den
servergebundenen Plan. `fixtures/csv-delivery/` enthält synthetische
Prüfdaten. Der [Jenkinsbuild](../dateninfrastruktur-jenkins-dev/README.md)
verpackt die versionierten Runner-, Vertrags- und Modellquellen.

Der eigenständige ClickHouse-Lader besitzt seinen eigenen Vertrag und
bleibt unabhängig vom CSV-Lieferjob.
