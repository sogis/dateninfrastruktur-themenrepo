import groovy.json.JsonOutput
import groovy.json.JsonSlurper
import java.nio.file.Files
import java.security.DigestInputStream
import java.security.MessageDigest

parameter('submissionId', required: true, description: 'UUID der Submission')
parameter('inputFile', type: 'path', required: true, description: 'Angelieferte CSV-Datei')
parameter('adminUrl', required: true, description: 'Basis-URL der internen Admin-API')
parameter('tokenUrl', required: true, description: 'Keycloak-Token-Endpunkt')
parameter('clientId', required: true, description: 'Technische Keycloak-Client-ID')
parameter('localHttp', type: 'boolean', defaultValue: false, description: 'HTTP im isolierten lokalen Stack erlauben')
parameter('s3Endpoint', required: true, description: 'Garage-Endpunkt')
parameter('s3AccessKey', required: true, description: 'Garage Writer Access Key')
parameter('s3Bucket', defaultValue: 'ch.so.daten', description: 'Privater Garage-Bucket')

parameter('clickhouseUrl', required: true, description: 'ClickHouse-HTTP-Endpunkt')
parameter('clickhouseUser', required: true, description: 'ClickHouse-Importbenutzer')

def clickhouseType = { column ->
    String type = switch (column.dataType) {
        case 'text', 'mtext', 'enumeration' -> 'String'
        case 'integer' -> 'Int64'
        case 'decimal' -> "Decimal(38, ${column.decimalPlaces as int})"
        case 'boolean' -> 'Bool'
        case 'date' -> 'Date32'
        case 'datetime' -> "DateTime64(3, 'UTC')"
        default -> throw new IllegalArgumentException('Unbekannter CSV-Datentyp.')
    }
    column.mandatory ? type : "Nullable(${type})"
}

def sha256 = { path ->
    def digest = MessageDigest.getInstance('SHA-256')
    Files.newInputStream(path).withCloseable { bytes ->
        new DigestInputStream(bytes, digest).transferTo(OutputStream.nullOutputStream())
    }
    HexFormat.of().formatHex(digest.digest())
}

def sqlPath = { path -> "'" + path.toString().replace("'", "''") + "'" }

action('deliver') { ctx ->
    def id = UUID.fromString(parameter('submissionId'))
    def admin = URI.create(parameter('adminUrl'))
    def allowHttp = parameter('localHttp')
    if (admin.scheme != 'https' && !(allowHttp && admin.scheme == 'http')) {
        throw new IllegalArgumentException('Die Admin-API benötigt HTTPS.')
    }
    def deliveryUrl = admin.resolve("/internal/deliveries/${id}/")
    def authorize = {
        ctx.run(OAuth2ClientCredentials) {
            tokenUrl = parameter('tokenUrl')
            clientId = parameter('clientId')
            clientSecret = secret('oauthClientSecret')
            allowInsecureHttp = allowHttp
        }.authorization()
    }
    def post = { operation, authorization, payload, responsePath ->
        ctx.run(Curl) {
            serverUrl = deliveryUrl.resolve(operation)
            method = 'POST'
            expectedStatusCode = 200
            headers = ['Authorization': authorization, 'Content-Type': 'application/json']
            if (payload != null) data = JsonOutput.toJson(payload)
            if (responsePath != null) outputFile = responsePath
        }
    }
    def authorization = authorize()
    def response = workPath('start.json')
    post('start', authorization, null, response)
    boolean rejected = false
    try {
        def state = new JsonSlurper().parse(response.toFile())
        def incoming = parameter('inputFile')
        if (!Files.isRegularFile(incoming) || Files.size(incoming) != state.inputSize ||
                sha256(incoming) != state.inputSha256) {
            throw new IllegalArgumentException('Die Eingabedatei stimmt nicht mit der Submission überein.')
        }

        def modelName = state.schemaModelName
        def modelDir = Files.createDirectory(workPath('models'))
        Files.writeString(modelDir.resolve(modelName + '.ili'), state.schemaModel)
        def snapshot = workPath('snapshot.csv')
        def access = parameter('s3AccessKey')
        def garage = parameter('s3Endpoint')
        def bucket = parameter('s3Bucket')
        if (state.mode == 'append') {
            def baseDir = Files.createDirectory(workPath('base'))
            def baseKey = state.baseCsvKey
            def base = ctx.run(S3Download) {
                accessKey = access
                secretKey = secret('s3SecretKey')
                endpoint = garage
                region = 'garage'
                bucketName = bucket
                key = baseKey
                downloadDir = baseDir
            }.files().getFirst()
            ctx.run(DuckDbSqlExecutor) {
                inMemory = true
                sqlFiles = [file('append.sql')]
                sqlParameters = [base: sqlPath(base), incoming: sqlPath(incoming), snapshot: sqlPath(snapshot)]
            }
        } else {
            Files.copy(incoming, snapshot)
        }

        def validation = ctx.run(CsvValidator) {
            dataFiles = [snapshot]
            modelNames = [modelName]
            modelDirectories = [modelDir]
            firstLineIsHeader = true
            valueSeparator = ','
            valueDelimiter = '"'
            encoding = 'UTF-8'
            logFile = workPath('validation.log')
            failOnError = false
        }
        if (!validation.valid()) {
            post('reject', authorization, [message: 'Der CSV-Snapshot verletzt das gebundene Modell.'], null)
            rejected = true
            throw new IllegalArgumentException('CSV-Snapshot abgelehnt. Details stehen im Validierungslog.')
        }
        def objectKey = state.candidatePrefix + 'snapshot.csv'
        ctx.run(S3Upload) {
            accessKey = access
            secretKey = secret('s3SecretKey')
            endpoint = garage
            region = 'garage'
            bucketName = bucket
            sourceFile = snapshot
            key = objectKey
            acl = 'private'
            contentType = 'text/csv'
        }

        def table = 'snapshot_' + id.toString().replace('-', '')
        def columns = state.columns.collect { column ->
            if (!(column.name ==~ /[A-Za-z][A-Za-z0-9_]{0,62}/)) {
                throw new IllegalArgumentException('Ungültiger CSV-Spaltenname.')
            }
            "`${column.name}` ${clickhouseType(column)}"
        }.join(', ')
        def ddl = "CREATE TABLE default.${table} (${columns}) ENGINE = MergeTree ORDER BY tuple()"
        ctx.run(SqlExecutor) {
            database = 'clickhouse'
            statements = [[sql: ddl.toString(), parameters: []]]
        }
        // The importer sends an empty INSERT for a header-only snapshot.
        boolean hasRows = Files.newBufferedReader(snapshot).withCloseable { reader ->
            reader.readLine()
            reader.read() != -1
        }
        if (hasRows) {
            ctx.run(CsvImport) {
                database = 'clickhouse'
                schemaName = 'default'
                tableName = table
                dataFile = snapshot
                firstLineIsHeader = true
                valueSeparator = ','
                valueDelimiter = '"'
                encoding = 'UTF-8'
            }
        }
        def countFile = workPath('count.json')
        ctx.run(Curl) {
            serverUrl = parameter('clickhouseUrl')
            method = 'POST'
            expectedStatusCode = 200
            user = parameter('clickhouseUser')
            password = secret('clickhousePassword')
            data = "SELECT count() AS objectCount FROM default.${table} FORMAT JSONEachRow"
            outputFile = countFile
        }
        def count = new JsonSlurper().parse(countFile.toFile()).objectCount as long
        post('complete', authorize(), [
            schemaId: state.schemaId, baseVersionId: state.baseVersionId,
            fileName: 'snapshot.csv', byteSize: Files.size(snapshot), sha256: sha256(snapshot),
            objectCount: count
        ], null)
    } catch (Exception error) {
        if (!rejected) {
            try {
                post('fail', authorize(), [message: 'Technischer Fehler bei der CSV-Verarbeitung.'], null)
            } catch (Exception notificationError) {
                error.addSuppressed(notificationError)
            }
        }
        throw error
    }
}

defaults 'deliver'
