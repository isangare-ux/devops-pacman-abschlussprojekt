#!/usr/bin/env bash
cd ..
set -euo pipefail

DOCX="dokumentation/10_uebergabe_und_betriebsanleitung.docx"

APP_COMMIT="a4c49abd81d9f5c4472b90110cb3fca5ae0348c2"
GITOPS_SHORT="f62e055"
GITOPS_COMMIT="f62e05517b68adc7fc166eb6313de1f411acca8b"

BACKUP="${DOCX}.bak_ap33"

echo "=== AP33: Finalen Git-Stand dokumentieren ==="
echo

if [[ ! -f "$DOCX" ]]; then
    echo "FEHLER: Datei nicht gefunden:"
    echo "$DOCX"
    exit 1
fi

echo "1. Backup erstellen ..."
cp -p "$DOCX" "$BACKUP"
echo "OK: $BACKUP"

echo
echo "2. GitOps-Commit in DOCX aktualisieren ..."

python3 - "$DOCX" "$GITOPS_SHORT" "$GITOPS_COMMIT" <<'PY'
import sys
import zipfile
import tempfile
import shutil
import os

docx, short_sha, full_sha = sys.argv[1:4]

with zipfile.ZipFile(docx, "r") as zin:
    document_xml = zin.read("word/document.xml")

text = document_xml.decode("utf-8")

if full_sha in text:
    print(f"INFO: Vollständige GitOps-SHA bereits vorhanden: {full_sha}")
    sys.exit(0)

if short_sha not in text:
    print(f"FEHLER: Kurz-SHA {short_sha} wurde nicht in word/document.xml gefunden.")
    sys.exit(2)

new_text = text.replace(short_sha, full_sha, 1)

fd, temp_path = tempfile.mkstemp(suffix=".docx")
os.close(fd)

try:
    with zipfile.ZipFile(docx, "r") as zin, \
         zipfile.ZipFile(temp_path, "w") as zout:

        for item in zin.infolist():
            data = zin.read(item.filename)

            if item.filename == "word/document.xml":
                data = new_text.encode("utf-8")

            zout.writestr(item, data)

    shutil.move(temp_path, docx)

finally:
    if os.path.exists(temp_path):
        os.remove(temp_path)

print(f"OK: {short_sha} wurde durch {full_sha} ersetzt.")
PY

echo
echo "3. DOCX-Struktur prüfen ..."

if unzip -t "$DOCX" >/dev/null 2>&1; then
    echo "OK: DOCX-ZIP-Struktur ist gültig."
else
    echo "FEHLER: DOCX-Struktur beschädigt."
    echo "Backup wiederherstellen mit:"
    echo "cp '$BACKUP' '$DOCX'"
    exit 3
fi

echo
echo "4. Beide finalen Commits prüfen ..."

TEXT="$(
    unzip -p "$DOCX" word/document.xml 2>/dev/null \
    | sed 's/<[^>]*>/ /g' \
    | tr -s ' '
)"

echo
echo "pacman-app:"
if printf '%s\n' "$TEXT" | grep -Fq "$APP_COMMIT"; then
    echo "OK: vollständiger Commit gefunden: $APP_COMMIT"
else
    echo "FEHLT: $APP_COMMIT"
fi

echo
echo "pacman-gitops:"
if printf '%s\n' "$TEXT" | grep -Fq "$GITOPS_COMMIT"; then
    echo "OK: vollständiger Commit gefunden: $GITOPS_COMMIT"
else
    echo "FEHLT: $GITOPS_COMMIT"
fi

echo
echo "=== AP33-Prüfung abgeschlossen ==="