# Genehmigte CSV-Verträge

`index.json` ist die abschliessende Liste der genehmigten Definitionen mit
SHA256 über die tatsächlichen Dateibytes. Keine Verzeichnissuche und keine
vom Benutzer gelieferten Modell-, Skript-, SQL- oder Objektpfade.

`schema/csv-definition-v1.schema.json` beschreibt den strikten v1-Vertrag.
Die anfängliche Definition `population-v1` unterstützt die sechs obligatorischen
Int32-Attribute des unveränderten Pilotmodells. Weitere Typen werden erst mit
nachgewiesener Verarbeitung in MA-G4 freigegeben. Unbekannte Typen führen
bereits beim Konfigurieren zur Ablehnung.

ADMIN verifiziert jeden Modellbytehash, den sortierten Modellsethash, das
kompilierte IlisMeta16-Modell sowie Attributreihenfolge, obligatorische Werte,
Zahlenbereiche und fachliche UNIQUE-Schlüssel. Die Attributliste in PG ist eine
geprüfte Projektion dieses Vertrags. Die fachliche Konfiguration und Rechte
liegen ausschliesslich in PG.

`compiled/*.imd` entsteht durch den festgelegten ili2c 5.6.9 mit `-oIMD16
--with-predefined --no-auto`. Der Compiler enthält das einzige importierte
Builtin-Modell INTERLIS. Die kompilierten Dateien sind keine freihändig
gepflegten Ersatzmodelle. Prüfung und reproduzierbare Neukompilation:

```sh
python3 ../dateninfrastruktur-dev-stack/scripts/test_csv_definitions.py
```

Die Kanonisierung für API-/Planhashes ist `di-json-v1`: UTF-8, sortierte
Objektschlüssel, explizite Nullwerte, geordnete Arrays, exakte Dezimalzahlen
(keine Float-Konvertierung). SHA256 wird über `di-json-v1\n` und den kanonischen
JSON-Text berechnet. Der Modellsethash hat dagegen keinen Präfix; sein
versioniertes JSON lautet `{"models":[...],"schemaVersion":1}`. Unabhängige
Testvektoren stehen unter `protocol/`.
