# CSV-Anlieferung mit GRETL 6

Der Job startet eine bestehende Submission als registrierter technischer
Keycloak-Principal. Er vergleicht die lokale UTF-8-CSV mit den bei der
Submission hinterlegten Dateiangaben. Bei Replace prüft er die Eingabedatei
als vollständigen Snapshot. Bei Append lädt er die aktuelle Basisdatei aus
Garage und verbindet die Spalten anhand der Headernamen. Die CSV verwendet
Komma als Trennzeichen und doppelte Anführungszeichen.

Der Job lädt einen gültigen Snapshot in den privaten Bucket `ch.so.daten`
und in eine neue ClickHouse-Tabelle `default.snapshot_<submissionId_ohne_Bindestriche>`.
Nach dem Import meldet er Grösse, SHA-256 und Zeilenzahl an Admin. Bei
erfolgreichem Abschluss wechselt die Submission auf `accepted`.
Bei fachlicher Ablehnung meldet er `rejected`. Das GRETL-Validierungslog
enthält die Details. Technische Fehler meldet er nach erfolgreichem Start
als `failed`, sofern die Admin-API erreichbar ist.

```sh
gretl run jobs/csv-delivery/job.groovy --config /pfad/gretl.json \
  --param submissionId="$SUBMISSION_ID" --param inputFile="$INPUT_FILE" \
  --param adminUrl="$ADMIN_URL" --param tokenUrl="$TOKEN_URL" \
  --param clientId=gretl-delivery --param s3Endpoint="$S3_ENDPOINT" \
  --param s3AccessKey="$S3_ACCESS_KEY" \
  --param clickhouseUrl="$CLICKHOUSE_URL" --param clickhouseUser="$CLICKHOUSE_USER"
```

Die GRETL-Konfiguration muss die Secret-Aliasse `oauthClientSecret` und
`s3SecretKey` und `clickhousePassword` bereitstellen. Der Datenbankalias
`clickhouse` unter `taskConfig` verwendet denselben Benutzer und
`passwordSecret: "clickhousePassword"`. Verwende JDBC 0.9.8 mit dem
All-in-one-JAR unter `lib/extensions/` und
`jdbc_ignore_unsupported_values=true` in der JDBC-URL. In der isolierten lokalen Compose-Instanz
kann `--param localHttp=true` für die internen HTTP-Endpunkte gesetzt
werden. `s3Bucket` ist optional und verwendet standardmässig
`ch.so.daten`.
