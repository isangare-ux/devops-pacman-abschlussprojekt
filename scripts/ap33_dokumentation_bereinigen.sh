#!/usr/bin/env bash
cd ..
set -euo pipefail

DIR="dokumentation"
MAIN="$DIR/10_uebergabe_und_betriebsanleitung.docx"

APP_COMMIT="a4c49abd81d9f5c4472b90110cb3fca5ae0348c2"
GITOPS_COMMIT="f051d6087d7f0437b852c21f2045122f42ab1c22"

DEV_DIGEST="sha256:114b3c9505cf4dde0e58101127f4e2ae6395928e7f013e33e7c8039cc2496490"
PROD_DIGEST="sha256:8a30554bf682a9a326f1227ec0e3978eab03b982bbe41e0d13ab1aad21d379f6"

echo "=== AP33 Dokumentationsbereinigung ==="
echo

if [[ ! -f "$MAIN" ]]; then
    echo "FEHLER: Hauptdokument fehlt:"
    echo "$MAIN"
    exit 1
fi

echo "1. DOCX-Struktur prüfen ..."

if ! unzip -t "$MAIN" >/dev/null 2>&1; then
    echo "FEHLER: Hauptdokument ist beschädigt."
    echo "Es wird nichts gelöscht."
    exit 2
fi

echo "OK: DOCX-Struktur gültig."

echo
echo "2. Wichtige AP33-Inhalte prüfen ..."

TEXT="$(
    unzip -p "$MAIN" word/document.xml 2>/dev/null \
    | sed 's/<[^>]*>/ /g' \
    | tr -s ' '
)"

CHECK_FAILED=0

check_value() {
    local label="$1"
    local value="$2"

    if printf '%s\n' "$TEXT" | grep -Fq "$value"; then
        echo "OK: $label"
    else
        echo "FEHLT: $label"
        CHECK_FAILED=1
    fi
}

check_value "pacman-app Commit" "$APP_COMMIT"
check_value "pacman-gitops Commit" "$GITOPS_COMMIT"
check_value "Dev Digest" "$DEV_DIGEST"
check_value "Prod Digest" "$PROD_DIGEST"
check_value "Argo CD Synced/Healthy" "Synced"
check_value "AP33 Betriebszustand" "Finaler Betriebszustand"

if [[ "$CHECK_FAILED" -ne 0 ]]; then
    echo
    echo "ABBRUCH: Nicht alle wichtigen Inhalte wurden gefunden."
    echo "Es wird nichts gelöscht."
    exit 3
fi

echo
echo "3. Zu löschende Sicherungsdateien anzeigen ..."

find "$DIR" -maxdepth 1 -type f \
    \( \
      -name '10_uebergabe_und_betriebsanleitung.docx.bak*' \
      -o -name '10_uebergabe_und_betriebsanleitung_vor_*.docx' \
    \) \
    -print

echo
echo "4. Sicherungsdateien löschen ..."

find "$DIR" -maxdepth 1 -type f \
    \( \
      -name '10_uebergabe_und_betriebsanleitung.docx.bak*' \
      -o -name '10_uebergabe_und_betriebsanleitung_vor_*.docx' \
    \) \
    -delete

echo
echo "5. Ergebnis prüfen ..."

FILES="$(
    find "$DIR" -maxdepth 1 -type f \
      -name '10_uebergabe_und_betriebsanleitung*' \
      -printf '%f\n'
)"

echo "$FILES"

COUNT="$(
    printf '%s\n' "$FILES" \
    | grep -c '^10_uebergabe_und_betriebsanleitung'
)"

if [[ "$COUNT" -eq 1 ]] && \
   [[ "$FILES" == "10_uebergabe_und_betriebsanleitung.docx" ]]; then

    echo
    echo "OK: Es existiert nur noch das finale Hauptdokument."
else
    echo
    echo "WARNUNG: Es existieren noch weitere Dateien."
    exit 4
fi

echo
echo "=== Bereinigung erfolgreich abgeschlossen ==="