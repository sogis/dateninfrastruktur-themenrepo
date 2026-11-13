# CSV-Anlieferung mit GRETL 6

Der Job startet eine bestehende Submission als registrierter technischer
Keycloak-Principal. Er vergleicht die lokale UTF-8-CSV mit den bei der
Submission hinterlegten Dateiangaben. Bei Replace prüft er die Eingabedatei
als vollständigen Snapshot. Bei Append lädt er die aktuelle Basisdatei aus
Garage und verbindet die Spalten anhand der Headernamen. Die CSV verwendet
Komma als Trennzeichen und doppelte Anführungszeichen.

Der Job lädt einen gültigen Snapshot in den privaten Bucket `ch.so.daten`.
Bei fachlicher Ablehnung meldet er `rejected`. Das GRETL-Validierungslog
enthält die Details. Technische Fehler meldet er nach erfolgreichem Start
als `failed`, sofern die Admin-API erreichbar ist.

```sh
gretl run jobs/csv-delivery/job.groovy --config /pfad/gretl.json \
  --param submissionId="$SUBMISSION_ID" --param inputFile="$INPUT_FILE" \
  --param adminUrl="$ADMIN_URL" --param tokenUrl="$TOKEN_URL" \
  --param clientId=gretl-delivery --param s3Endpoint="$S3_ENDPOINT" \
  --param s3AccessKey="$S3_ACCESS_KEY"
```

Die GRETL-Konfiguration muss die Secret-Aliasse `oauthClientSecret` und
`s3SecretKey` bereitstellen. In der isolierten lokalen Compose-Instanz
kann `--param localHttp=true` für die internen HTTP-Endpunkte gesetzt
werden. `s3Bucket` ist optional und verwendet standardmässig
`ch.so.daten`.
