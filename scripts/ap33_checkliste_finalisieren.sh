cd ..
#!/usr/bin/env bash
set -euo pipefail

DOCX="dokumentation/10_uebergabe_und_betriebsanleitung.docx"

if [[ ! -f "$DOCX" ]]; then
    echo "FEHLER: $DOCX nicht gefunden."
    exit 1
fi

python3 - "$DOCX" <<'PY'
import sys
import os
import shutil
import tempfile
import zipfile

docx = sys.argv[1]

replacements = {
    "Vor Abgabe aktuell erfassen.": None,
}

with zipfile.ZipFile(docx, "r") as zin:
    xml = zin.read("word/document.xml").decode("utf-8")

old_repo = "Finale Repository-Commits"
old_digest = "Finale Image-Digests"

repo_status = (
    "Erfasst und mit den finalen Git-Ständen abgeglichen: "
    "pacman-app a4c49abd81d9f5c4472b90110cb3fca5ae0348c2; "
    "pacman-gitops f051d6087d7f0437b852c21f2045122f42ab1c22."
)

digest_status = (
    "Erfasst und mit den tatsächlich laufenden Pods abgeglichen. "
    "Dev: sha256:114b3c9505cf4dde0e58101127f4e2ae6395928e7f013e33e7c8039cc2496490; "
    "Prod: sha256:8a30554bf682a9a326f1227ec0e3978eab03b982bbe41e0d13ab1aad21d379f6."
)

# Nur die Tabellenzeilen gezielt über ihren Kontext ersetzen.
repo_pos = xml.find(old_repo)
if repo_pos == -1:
    raise SystemExit("FEHLER: Zeile 'Finale Repository-Commits' nicht gefunden.")

digest_pos = xml.find(old_digest)
if digest_pos == -1:
    raise SystemExit("FEHLER: Zeile 'Finale Image-Digests' nicht gefunden.")

def replace_next_status(xml, start_pos, new_status):
    marker = "Vor Abgabe aktuell erfassen."
    pos = xml.find(marker, start_pos)
    if pos == -1:
        raise SystemExit("FEHLER: Erwarteter Status nicht gefunden.")
    return xml[:pos] + new_status + xml[pos + len(marker):]

xml = replace_next_status(xml, repo_pos, repo_status)

# Position nach erster Änderung neu bestimmen
digest_pos = xml.find(old_digest)
xml = replace_next_status(xml, digest_pos, digest_status)

fd, tmp = tempfile.mkstemp(suffix=".docx")
os.close(fd)

try:
    with zipfile.ZipFile(docx, "r") as zin, \
         zipfile.ZipFile(tmp, "w") as zout:

        for item in zin.infolist():
            data = zin.read(item.filename)

            if item.filename == "word/document.xml":
                data = xml.encode("utf-8")

            zout.writestr(item, data)

    shutil.move(tmp, docx)

finally:
    if os.path.exists(tmp):
        os.remove(tmp)

print("OK: Finale Repository-Commits aktualisiert.")
print("OK: Finale Image-Digests aktualisiert.")
PY

echo
echo "DOCX-Struktur prüfen ..."

unzip -t "$DOCX" >/dev/null

echo "OK: DOCX-Struktur gültig."