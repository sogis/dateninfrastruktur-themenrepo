# Abstimmungsresultate aus eCH-0252

Anwendungs-ID: `staatskanzlei.abstimmungsresultate`. Die Pipeline `abstimmungsresultate.hpl`
verarbeitet eine eCH-0252-v1-Resultatlieferung aus VeWork. Exportiert werden nur
**eidgenössische und kantonale Abstimmungen**. Eine CSV-Zeile entspricht
**Geschäftskomponente × Gemeinde**. Vorlage, Gegenvorschlag und Stichfrage sind
separate, über die Geschäftsgruppe verknüpfte Komponenten.

## Starten

Im Hop Application Launcher **Abstimmungsresultate – eCH-0252** auswählen,
XML-Datei und einen bestehenden Ausgabeordner angeben, dann **Starten**.
Die Parameter bleiben `INPUT_XML` und `OUTPUT_DIR`; beide Pfade müssen im Launcher
ausserhalb des verwalteten Checkouts liegen. Der Katalog bleibt
`shared/hop/applications.yaml`, die Formularbeschreibung steht in
`abstimmungsresultate.launcher.yaml`.

Für den direkten Start in Hop dieselben Parameter setzen und die lokale
Run-Konfiguration `launcher-local` verwenden. Deren Metadaten sind unter
`shared/hop/metadata` versioniert. Mit `hop-run.sh` beispielsweise:

```sh
hop-run.sh \
  -f /pfad/zum/checkout/staatskanzlei/abstimmungsresultate/hop/abstimmungsresultate.hpl \
  -r launcher-local \
  -p 'INPUT_XML=/pfad/zur/lieferung.xml,OUTPUT_DIR=/pfad/zur/ausgabe'
```

Hop muss dabei die versionierte Run-Konfiguration in seinem Metadatenverzeichnis
oder über ein entsprechend konfiguriertes Hop-Projekt finden. Der Launcher bindet
`shared/hop/metadata` selbst ein.

## Eingabe und Prüfungen

Unterstützt wird `delivery/voteBaseDelivery` im Namespace
`http://www.ech.ch/xmlns/eCH-0252/1`. Die Einflussbereichsangaben des vorliegenden
VeWork-Exports verwenden `http://www.ech.ch/xmlns/eCH-0155/5`. XPath-Ausdrücke prüfen
die Namespace-URIs; XML-Präfixe und ein Default-Namespace sind beliebig.
Die Lieferung muss Resultate für alle enthaltenen Gemeinde-Auszählkreise (`MU`)
enthalten. Andere Lieferarten, eCH-0252-Versionen und Auszählkreistypen werden
abgelehnt. Deutsche Titel sind erforderlich, ein fehlender Kurztitel bleibt leer.

`Filter Rows` lässt nach den Prüfungen nur Geschäfte mit
`domainOfInfluenceType = CH` oder `CT` durch. Reine Gemeindeabstimmungen (`MU` auf
Geschäftsebene) enden im Transform `Gemeindeabstimmungen verwerfen`.
Gemeinde-Auszählkreise eidgenössischer und kantonaler Geschäfte bleiben enthalten.
Die gesamte Lieferung wird weiterhin geprüft, einschliesslich ausgefilterter
Gemeindeabstimmungen. Enthält sie keine CH-/CT-Geschäfte, bricht die Pipeline mit
einer verständlichen Meldung ab und lässt eine vorhandene CSV unverändert.

Die Pipeline prüft vor der Ausgabe:

- Geschäftsanzahl gegen `numberOfEntries` und übereinstimmende Abstimmungstage.
- Eindeutige Geschäft-IDs und Gemeinde-IDs innerhalb eines Geschäfts. Schlüssel
  müssen ohne Rand-Leerzeichen vorliegen; mehrfache skalare Werte werden abgelehnt.
- Hauptgeschäft-Verweise auf eine vorhandene Vorlage, ohne Selbstverweis;
  Gegenvorschläge und Stichfragen benötigen einen solchen Verweis.
- Pflichtwerte, unterstützte Codes, gültige Datumswerte und nichtnegative ganze
  Anzahlen im eCH-Wertebereich 0–9’999’999; eine gelieferte Beteiligung liegt bei 0–100.
- Eindeutige deutsche Titel und eindeutige Einzelklassifikationen der
  Stimmberechtigten.
- `eingegangen = ungültig + leer + gültig` sowie
  `gültig = beide Stimmenzahlen + Stimmen ohne Antwort`.

Fehlende `countOfVotesWithoutAnswer` werden nur im internen Prüffeld als 0
behandelt. In der CSV bleibt der Wert leer. Die vier Stimmberechtigten-Teilsummen
stammen aus Einzelklassifikationen ohne die jeweils andere Dimension;
Kreuzklassifikationen werden nicht hinzuaddiert. Fehlende Teilsummen werden nicht
aus anderen Angaben abgeleitet.

Eine mehrfach verwendete Bundes-ID erzeugt **eine Warnmeldung pro Lieferung**
mit Lieferungs-ID, erster doppelter Bundes-ID und Anzahl Wiederholungen. Die
Bundes-ID führt zu keiner Deduplizierung; `bund_id` ist kein Schlüssel.

Diese Prüfungen erfolgen mit XPath-Kontrollfeldern und `Data Validator`, ohne eine
vollständige XSD-Validierung oder Abrufe aus dem Netz. Ungültige Zeilen brechen die
Pipeline ab; sie werden nicht stillschweigend verworfen.

## CSV

Dateiname: `${OUTPUT_DIR}/abstimmungsresultate_<abstimmungstag>.csv`, beispielsweise
`abstimmungsresultate_2026-03-08.csv`. Ein erfolgreicher Wiederholungslauf ersetzt
die Datei. `Sort Rows` puffert den gesamten Datenstrom und sortiert nach
Abstimmungstag, Geschäft-ID und Gemeinde-BFS-Nummer. `Text File Output` öffnet die
Datei erst mit der ersten vollständig geprüften Ausgabezeile. Auch ein Prüffehler
in der letzten Eingabezeile lässt eine bestehende Ergebnisdatei unverändert.
Ein Fehler beim eigentlichen Schreiben, etwa ein voller Datenträger, wird damit
nicht atomar abgesichert.

Die feste Reihenfolge der 32 Spalten lautet:

| Gruppe | Spalten in Reihenfolge |
| --- | --- |
| Geschäft | `abstimmungstag`, `geschaeft_id`, `hauptgeschaeft_id`, `geschaeftsgruppe_id`, `bund_id`, `ebene`, `einflussbereich_id`, `titel`, `kurztitel`, `geschaeftstyp` |
| Gemeinde | `gemeinde_bfs_nr`, `gemeinde_name` |
| Stimmberechtigte | `stimmberechtigte`, `stimmberechtigte_schweizer`, `stimmberechtigte_auslandschweizer`, `stimmberechtigte_maennlich`, `stimmberechtigte_weiblich` |
| Stimmrechtsausweise | `stimmrechtsausweise_urne`, `stimmrechtsausweise_brieflich` |
| Status | `vollstaendig_ausgezaehlt`, `freigegeben_am`, `gesperrt_am` |
| Stimmzettel | `stimmbeteiligung_prozent`, `stimmzettel_eingegangen`, `stimmzettel_ungueltig`, `stimmzettel_leer`, `stimmzettel_gueltig` |
| Stimmen | `ja_stimmen`, `nein_stimmen`, `stichfrage_hauptvorlage_stimmen`, `stichfrage_gegenvorschlag_stimmen`, `stimmen_ohne_antwort` |

`voteSubType` wird als `1 → vorlage`, `2 → gegenvorschlag`, `3 → stichfrage`
abgebildet. Bei Typ 1/2 sind Ja/Nein gefüllt und die Stichfrage-Spalten numerische
NULLs; bei Typ 3 gilt das Umgekehrte. `geschaeftsgruppe_id` ist die erste nicht
leere ID aus `hauptgeschaeft_id` und `geschaeft_id`.

`ebene` beschreibt das exportierte Geschäft: `CH → bund`, `CT → kanton`.
Die Ergebniszeile beschreibt stets eine Gemeinde. Alle IDs bleiben Text,
einschliesslich führender Nullen. `bund_id` stammt ausschliesslich aus
`otherIdentification` mit `idName = idBund`.

Ausgabe gemäss [Datenportal-Datenformat](https://sogis.github.io/datenportal-dokumentation/datenpublikation/main/#datenformat):
UTF-8 ohne BOM, Semikolon, Kopfzeile, Unix-Zeilenenden, Dezimalpunkt, keine
Tausendertrennzeichen und leere NULL-Werte. Texte werden bei Bedarf in doppelte
Anführungszeichen eingeschlossen; enthaltene Anführungszeichen werden verdoppelt.
Anzahlen werden als ganze Zahlen ausgegeben, Boolean-Werte als `true`/`false`.

Datum: `YYYY-MM-DD`. Zeitstempel werden als ISO-Zeitstempel mit dem festen Offset
`+01:00` ausgegeben. Die Eingabe erwartet Sekunden und einen expliziten Offset oder
`Z`, beispielsweise `2026-03-08T12:30:00+02:00`; daraus wird korrekt
`2026-03-08T11:30:00+01:00`. Das ist ein fester Ausgabeoffset und keine Umstellung
auf Schweizer Sommerzeit. Die Umrechnung und Formatierung erfolgen über die
Hop-Datumsmetadaten.

## Aufbau und Abnahme

Die Pipeline besteht aus 29 Standard-Transforms. Sie verwendet `Get Variables`,
`Get Data From XML`, `Data Validator`, `Filter Rows`, `Write to Log`,
`Select Values`, `Add Constants`, `Coalesce`, `Calculator`, `Value Mapper`,
`Concat Fields`, `Switch / Case`, `Dummy`, `Abort`, `Sort Rows` und `Text File Output`.
Es gibt keine JavaScript-, Java- oder anderen Script-Transforms. Hilfsfelder
werden vor der CSV-Ausgabe entfernt. Beide Stimmenzweige haben dieselbe
Feldreihenfolge und dieselben Datentypen.

Die Integrationstests starten die echte Hop-Engine. Mit Hop 2.19.0 und einer
geeigneten Java-Installation:

```sh
python3 staatskanzlei/abstimmungsresultate/hop/tests/test_pipeline.py \
  --hop-home /pfad/zu/hop \
  --java-home /pfad/zum/jdk \
  --input-xml /pfad/zu/20260308_Abstimmungen_ech0252.xml \
  --launcher
```

Ohne `--input-xml` werden synthetische Lieferungen verwendet und die Abnahme mit
der Originaldatei übersprungen. `--launcher` prüft zusätzlich den Ausführungsdienst
des installierten Launcher-JARs mit dem bestehenden Katalog und Formular.
`LauncherSmoke.java` ist ausschliesslich ein Testharness; die Pipeline benötigt
keinen kompilierten Anwendungscode. Testdaten, Ausgaben und Logs liegen in einem
temporären Verzeichnis, dessen Pfad beim Start ausgegeben wird.

Die Originaldatei ergibt 1’040 Datenzeilen, darunter 104 Stichfragen, aus zehn
eidgenössischen und kantonalen Geschäftskomponenten. Die kommunale Abstimmung
`IPQ247` in Olten wird ausgefiltert. Die Tests prüfen die Einzelwerte von
Aedermannsdorf, die Olten-Stimmberechtigten beim Bundesgeschäft,
Stichfrage-Summen 36’128 / 57’240 / 3’158, die Warnung zu Bundes-ID 6840,
CSV-Escaping, NULLs, Offset-Umrechnung und den Erhalt bestehender Ausgaben bei
ungültigen Lieferungen, einschliesslich Fehlern in der letzten Zeile.

Beispieldaten werden nicht mitversioniert. Historische Zusammenführung, Parquet,
Detailtabellen und Datenportal-Publikation sind nicht Bestandteil dieser Anwendung.
