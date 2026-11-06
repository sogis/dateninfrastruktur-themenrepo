# dateninfrastruktur-themenrepo

Im gemeinsamen Dateninfrastruktur-Workspace vor repoübergreifender Arbeit
`../AGENTS.md` ausdrücklich lesen und die Repo-Grenzen verifizieren. Bei einem
Einzelclone gelten die lokalen Regeln und Bedienhinweise im README. Für
repoübergreifende Aufträge zuerst den verifizierten Workspace bereitstellen.

Dieses Repo besitzt die fachlichen CSV-Definitionen, die gepinnten Modelle
und den festen GRETL-Runner. Der Stack bindet diese Inputs ins Runnerbundle
ein. Der Runner verarbeitet nur gebundene Lieferpläne und belegt seine
Kandidatenausgaben. Versions-/Schemabezüge und Hashbindungen erhalten.

Der eigenständige ClickHouse-Ladeweg besitzt seinen eigenen dokumentierten
Aufruf. Für Build, Vertragstests und Laufzeitinputs gilt README.md.
Fachliche Rechte liegen in PostgreSQL; der aktuelle Lieferweg spiegelt
Personenrechte und Teams nicht als Jobkonfiguration.
