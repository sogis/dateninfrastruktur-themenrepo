# AGENTS.md – dateninfrastruktur-themenrepo

## Vor Beginn lesen

Lies ausdrücklich `../AGENTS.md` und `../dateninfrastruktur-dev-stack/docs/implementation/grundinstallation/AUFTRAG_GRUNDINSTALLATION.md` sowie den zur aktuellen Rolle gehörenden Startprompt im selben Dokumentationsordner. Fehlt `../AGENTS.md`, lies ersatzweise `../dateninfrastruktur-dev-stack/docs/implementation/grundinstallation/templates/AGENTS.workspace.md`. Verlasse dich nicht auf automatische Vererbung über Git-Grenzen. Weitere betroffene Schwesterrepos haben eigene AGENTS-Dateien.

Diese Regeln gelten für Implementierung **und** Review. Ein Reviewauftrag erlaubt keine Änderungen an Produktdateien, Tests, Anforderungen oder AGENTS-Dateien; Befunde melden, nicht selbst reparieren. Builds/Tests nur mit eigenen Laufzeitdaten. Quellrepos, fremde Änderungen und laufende fremde Instanzen erhalten; keine Secrets in Git oder Berichten.

## Verantwortung

Dieses Repo enthält Metadaten, Jobdefinitionen, den gemeinsamen Jenkinsfile-Vertrag und die bestehende Publikationslogik für den lokalen Portal-Bootstrap.

## Besondere Regeln

- Organisations-/Datensatzstruktur, INTERLIS-Modellnamen, fachliche IDs und Scanner-YAML-Dateinamen zunächst erhalten.
- Aktive Lieferungs-, Manifest-, S3-, Reload- und Git-Ziele ausschliesslich lokal beziehungsweise deaktiviert. Beschreibende Herkunfts-URLs sind davon zu unterscheiden.
- Bestehenden `initializePublication`-Ablauf verwenden. Eine gültige Veröffentlichung ohne gelieferte Fachdaten genügt; keine gefälschte DuckDB-Headerdatei.
- Modelle gemäss vorhandenem Manifest durch den Jenkins-Runtime-Build bereitstellen. Keine vollständige lokale `shared/models`-Ablage voraussetzen.
- Kein CSV-Ladeweg nach ClickHouse, keine Historisierung, keine neue Berechtigungspipeline und kein allgemeiner INTERLIS-nach-ClickHouse-Generator in dieser Etappe.
- Quell- und Zielkopie auseinanderhalten; der Jenkins-Seed verwendet das neue Repo. Beim Kopieren dessen vorab abgelegte AGENTS-Datei erhalten.

## Nachweise

Scanner-/Seed-Vertrag und lokale Erstpublikation im neuen Stack prüfen. Manifestreferenzen und echte lesbare Katalogartefakte nachweisen. Keine externen Writes/Reloads und keine geschützten Testinhalte in öffentlichen Publikationsartefakten. Phasenberichte zentral im Dev-Stack führen.
