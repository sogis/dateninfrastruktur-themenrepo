# dateninfrastruktur-themenrepo

MA-F verwendet den gemeinsamen Compose-Stack und den DB-Katalog. Der normale
Stackstart startet keine Publikation. Legacy-S3-Publikation bei
`catalogSourceType=database` wird vor Taskaktionen abgewiesen; lokale
Legacyartefakte mit `s3Publish=false` und eigenständige Ladejobs bleiben möglich.
Bestehender ClickHouse-Lader, Daten und private Archive werden nicht zurückgesetzt.


Fachliches Vertragsrepo für Organisationen, Datensätze, Shared Defaults und
den Gradle-Build-Vertrag des GRETL-Datenportals in der lokalen
Dateninfrastruktur-Grundinstallation.

## Rolle im Gesamtsystem

Dieses Repo ist die fachliche Source of Truth fuer alles, was das
Jenkins-Plugin aus dem Themenrepo liest.

Hierher gehoeren:

- Organisationen und Datensaetze
- `gretl-datenportal-job.yaml`
- `shared/gretl-datenportal-defaults.yaml`
- `shared/gretl-datenportal-teams.yaml`
- `shared/Jenkinsfile`
- `shared/gradle/gradle-build.properties`
- gemeinsame Gradle-Initialisierung fuer GRETL und Offline-Aufloesung

Nicht hierher gehoeren:

- Scanner-, UI- und Seed-Logik des Plugins:
  [dateninfrastruktur-jenkins-gretl-plugin](https://github.com/sogis/dateninfrastruktur-jenkins-gretl-plugin)
- lokaler Jenkins, JCasC, Offline-Bundle-Bau und Docker-Image:
  [dateninfrastruktur-jenkins-dev](https://github.com/sogis/dateninfrastruktur-jenkins-dev)

## Aktueller Vertragsstand

Der aktuelle Vertrag ist bewusst streng:

- Das Startformular ist fix und nicht mehr repository-konfigurierbar.
- `gui`-Bloecke und `dataset-gui.yaml` werden nicht mehr unterstuetzt.
- Eine Organisation braucht eine gueltige `gretl-datenportal-job.yaml`.
- Ein Datensatz ist ein Unterordner mit genau einer `.xtf`- oder `.xml`-Datei.
- `permissions.read` und `permissions.build` referenzieren Teams aus
  `shared/gretl-datenportal-teams.yaml`.
- Der Standardtask `publishToDatenportal` bereitet Lieferungen mit GRETL und
  SQL vor. Bei S3-Freigabe publiziert er vollständige Gesamt-XTF über
  `current.json`; der versionierte DuckDB-View-Katalog wird gemeinsam mit den XTF freigegeben.
  Zusätzlich freigegebenes Git-Rückschreiben betrifft nur das
  ausgewählte Datenblatt. Danach wird `opendata.rdf` für freigegebene Datensätze
  und Serienausgaben aktualisiert; ein Portal-Reload ist optional.
  `initializePublication` im Root erzeugt administrativ den ersten Stand.
  Details: [SQL-Lieferverarbeitung](docs/biblios/lieferverarbeitung.adoc).
- Die gemeinsame Datei `shared/gradle/datenportal-s3.gradle` stellt die
  zentrale S3-Konfiguration und `registerDatenportalS3Upload` für
  organisationsspezifische Upload-Tasks bereit. Endpoint und Credentials
  kommen aus der Jenkins-/Gradle-Runtime und werden nicht in Jobs abgelegt.
- `shared/gradle/gradle-build.properties` bleibt die Source of Truth fuer
  Plugin-Versionen, Repository-URLs und Offline-Seed-Koordinaten.

## Zentrale Workflows

Der lokale Jenkins erzeugt den Seed-Job nicht mehr ueber JCasC. Stattdessen
provisioniert das Plugin den Job `gretl-datenportal-seed` automatisch.
Themenrepo-Aenderungen werden nach dem naechsten Seed-Lauf in Jenkins-Jobs
materialisiert.

Der lokale Jenkins verwendet fuer die Authentisierung einen JCasC-Local-
Security-Realm; eine AD-/LDAP-Umgebung ist fuer lokale Tests nicht notwendig.
Im Modus `managed-git` verarbeitet der Seed-Lauf den committed Stand des
konfigurierten Branches. Im lokalen Compose-Stack gilt `working-tree`: auch
uncommittete Änderungen werden beim nächsten Seed als Snapshot übernommen.
Danach die materialisierten Jobs prüfen. S3 bleibt in beiden Fällen die
Quelle des angenommenen Gesamtstands; Seeden allein publiziert kein Datenblatt. Die lokalen Konten
und der Bootstrap-Ablauf sind im Schwester-Repository
[dateninfrastruktur-jenkins-dev](https://github.com/sogis/dateninfrastruktur-jenkins-dev)
dokumentiert.

### Neue Organisation anlegen

Die Struktur, Pflichtfelder und ein minimales Beispiel sind in der Langform-Doku
unter [docs/biblios/workflow-neue-organisation.adoc](docs/biblios/workflow-neue-organisation.adoc)
beschrieben.

### Neuen Datensatz anlegen

Die Datensatzstruktur, Scan-Regeln und Validierungsgrenzen sind unter
[docs/biblios/workflow-neuer-datensatz.adoc](docs/biblios/workflow-neuer-datensatz.adoc)
beschrieben.

### Build- und Offline-Vertrag pruefen

Online-Test:

```bash
cd ../dateninfrastruktur-themenrepo
./gradlew -I "$PWD/shared/gradle/init.gradle" -p agi tasks
```

Offline-Test nach Bundle-Bau im Schwester-Repo:

```bash
cd ../dateninfrastruktur-jenkins-dev
./bin/build-offline-bundle.sh

cd ../dateninfrastruktur-themenrepo
GRADLE_USER_HOME="../dateninfrastruktur-jenkins-dev/build/offline-bundle/gradle-user-home" \
DATENINFRASTRUKTUR_OFFLINE_JARS_DIR="../dateninfrastruktur-jenkins-dev/build/offline-bundle/jars" \
./gradlew --offline -I "$PWD/shared/gradle/init.gradle" -p statistikdienst verifyPluginSetup
```

## Langform-Doku

Die kanonische technische Doku liegt unter
[docs/biblios/index.adoc](docs/biblios/index.adoc).

Empfohlene Einstiege:

- [Zweck des Themenrepos](docs/biblios/zweck.adoc)
- [Erwartete Repository-Struktur](docs/biblios/struktur.adoc)
- [Gradle-Build-Vertrag](docs/biblios/gradle-build-vertrag.adoc)
- [Offline-Bundle und Java-Laufzeiten](docs/biblios/offline-und-java.adoc)

## Schwester-Repositories

- [dateninfrastruktur-jenkins-gretl-plugin](https://github.com/sogis/dateninfrastruktur-jenkins-gretl-plugin)
  ist die kanonische Doku fuer Scanner, Startformular, Berechtigungen,
  Seed-Builder und Pipeline-Rendering.
- [dateninfrastruktur-jenkins-dev](https://github.com/sogis/dateninfrastruktur-jenkins-dev)
  ist die kanonische Doku fuer lokalen Jenkins, Offline-Bundle, Plugin-Installationsloop
  und Docker-/Airgap-Tests.
