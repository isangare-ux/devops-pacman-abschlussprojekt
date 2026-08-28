cd ..
#!/usr/bin/env bash
set -euo pipefail

DIR="dokumentation"
MAIN="$DIR/abschlussdokumentation.docx"

echo "=== Abschlussdokumentation bereinigen ==="
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
echo "2. Dokumentinhalt grob prüfen ..."

TEXT="$(
    unzip -p "$MAIN" word/document.xml 2>/dev/null \
    | sed 's/<[^>]*>/ /g' \
    | tr -s ' '
)"

if [[ -z "$TEXT" ]]; then
    echo "FEHLER: Im Hauptdokument konnte kein Text gelesen werden."
    echo "Es wird nichts gelöscht."
    exit 3
fi

echo "OK: Dokument enthält lesbaren Inhalt."

echo
echo "3. Zu löschende Sicherungsdateien anzeigen ..."

find "$DIR" -maxdepth 1 -type f \
    \( \
      -name 'abschlussdokumentation.docx.bak*' \
      -o -name 'abschlussdokumentation_vor_*.docx' \
    \) \
    -print

echo
echo "4. Sicherungsdateien löschen ..."

find "$DIR" -maxdepth 1 -type f \
    \( \
      -name 'abschlussdokumentation.docx.bak*' \
      -o -name 'abschlussdokumentation_vor_*.docx' \
    \) \
    -delete

echo
echo "5. Ergebnis prüfen ..."

FILES="$(
    find "$DIR" -maxdepth 1 -type f \
      -name 'abschlussdokumentation*' \
      -printf '%f\n'
)"

echo "$FILES"

COUNT="$(
    printf '%s\n' "$FILES" \
    | grep -c '^abschlussdokumentation'
)"

if [[ "$COUNT" -eq 1 ]] && \
   [[ "$FILES" == "abschlussdokumentation.docx" ]]; then

    echo
    echo "OK: Es existiert nur noch die finale Abschlussdokumentation."
else
    echo
    echo "WARNUNG: Es existieren noch weitere Dateien."
    exit 4
fi

echo
echo "=== Bereinigung erfolgreich abgeschlossen ==="