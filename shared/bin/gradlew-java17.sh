#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GRADLE_WRAPPER="$REPO_ROOT/gradlew"
JAVA17_HOME="${GRADLE_JAVA_HOME_17:-}"

java_major_version() {
  "$1/bin/java" -version 2>&1 | awk -F'[".]' '/version/ {print $2; exit}'
}

if [ -z "$JAVA17_HOME" ]; then
  echo "GRADLE_JAVA_HOME_17 ist nicht gesetzt. Jenkins muss fuer GRETL/Gradle ein Java-17-Home exportieren." >&2
  exit 1
fi

if [ ! -x "$JAVA17_HOME/bin/java" ]; then
  echo "GRADLE_JAVA_HOME_17 verweist nicht auf ein gueltiges Java-Home: $JAVA17_HOME" >&2
  exit 1
fi

if [ "$(java_major_version "$JAVA17_HOME")" != "17" ]; then
  echo "GRADLE_JAVA_HOME_17 verweist nicht auf Java 17: $JAVA17_HOME" >&2
  exit 1
fi

if [ ! -f "$GRADLE_WRAPPER" ]; then
  echo "Gradle wrapper not found: $GRADLE_WRAPPER" >&2
  exit 1
fi

export JAVA_HOME="$JAVA17_HOME"
export PATH="$JAVA_HOME/bin:$PATH"

chmod +x "$GRADLE_WRAPPER"
exec "$GRADLE_WRAPPER" "$@"
