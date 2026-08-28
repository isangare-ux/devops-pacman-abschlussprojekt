#!/usr/bin/env bash
cd ..
set -euo pipefail

DOCX="dokumentation/10_uebergabe_und_betriebsanleitung.docx"

APP_COMMIT="a4c49abd81d9f5c4472b90110cb3fca5ae0348c2"
GITOPS_COMMIT="f051d6087d7f0437b852c21f2045122f42ab1c22"

DEV_IMAGE="ghcr.io/isangare-ux/pacman-app:a4c49abd81d9f5c4472b90110cb3fca5ae0348c2"
DEV_DIGEST="sha256:114b3c9505cf4dde0e58101127f4e2ae6395928e7f013e33e7c8039cc2496490"

PROD_IMAGE="ghcr.io/isangare-ux/pacman-app:2ae1f2e41c992fdbb81107aac79e66afe7ef2ea1"
PROD_DIGEST="sha256:8a30554bf682a9a326f1227ec0e3978eab03b982bbe41e0d13ab1aad21d379f6"

MARKER="AP33 – Finaler Betriebszustand und Live-Demo-Stand"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="${DOCX}.bak_${TIMESTAMP}"

echo "============================================================"
echo " AP33 – Betriebszustand in Übergabedokumentation übernehmen"
echo "============================================================"
echo

if [[ ! -f "$DOCX" ]]; then
    echo "FEHLER: DOCX-Datei nicht gefunden:"
    echo "$DOCX"
    exit 1
fi

echo "1. DOCX-Struktur vor Änderung prüfen ..."

if ! unzip -t "$DOCX" >/dev/null 2>&1; then
    echo "FEHLER: Die DOCX-Datei ist vor der Änderung nicht gültig."
    exit 2
fi

echo "OK: DOCX-Struktur gültig."

echo
echo "2. Backup erstellen ..."

cp -p "$DOCX" "$BACKUP"

echo "OK: $BACKUP"

echo
echo "3. AP33-Abschnitt ergänzen ..."

python3 - \
    "$DOCX" \
    "$MARKER" \
    "$APP_COMMIT" \
    "$GITOPS_COMMIT" \
    "$DEV_IMAGE" \
    "$DEV_DIGEST" \
    "$PROD_IMAGE" \
    "$PROD_DIGEST" <<'PY'

import sys
import os
import shutil
import tempfile
import zipfile
import xml.etree.ElementTree as ET

(
    docx,
    marker,
    app_commit,
    gitops_commit,
    dev_image,
    dev_digest,
    prod_image,
    prod_digest,
) = sys.argv[1:9]

W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
XML_NS = "http://www.w3.org/XML/1998/namespace"

ET.register_namespace("w", W_NS)

def qn(tag):
    return f"{{{W_NS}}}{tag}"

with zipfile.ZipFile(docx, "r") as zin:
    xml_data = zin.read("word/document.xml")

root = ET.fromstring(xml_data)

existing_text = "".join(
    node.text or ""
    for node in root.iter(qn("t"))
)

if marker in existing_text:
    print("INFO: AP33-Abschnitt ist bereits vorhanden.")
    print("Es wurde kein zweiter Abschnitt angelegt.")
    sys.exit(0)

body = root.find(qn("body"))

if body is None:
    print("FEHLER: word/document.xml enthält keinen Dokumentkörper.")
    sys.exit(3)

sect_pr = body.find(qn("sectPr"))

def add_paragraph(text="", bold=False, style=None):
    p = ET.Element(qn("p"))

    if style:
        p_pr = ET.SubElement(p, qn("pPr"))
        p_style = ET.SubElement(p_pr, qn("pStyle"))
        p_style.set(qn("val"), style)

    r = ET.SubElement(p, qn("r"))

    if bold:
        r_pr = ET.SubElement(r, qn("rPr"))
        ET.SubElement(r_pr, qn("b"))

    t = ET.SubElement(r, qn("t"))
    t.set(f"{{{XML_NS}}}space", "preserve")
    t.text = text

    if sect_pr is not None:
        index = list(body).index(sect_pr)
        body.insert(index, p)
    else:
        body.append(p)

def add_label_value(label, value):
    p = ET.Element(qn("p"))

    r1 = ET.SubElement(p, qn("r"))
    r1_pr = ET.SubElement(r1, qn("rPr"))
    ET.SubElement(r1_pr, qn("b"))

    t1 = ET.SubElement(r1, qn("t"))
    t1.set(f"{{{XML_NS}}}space", "preserve")
    t1.text = f"{label}: "

    r2 = ET.SubElement(p, qn("r"))
    t2 = ET.SubElement(r2, qn("t"))
    t2.set(f"{{{XML_NS}}}space", "preserve")
    t2.text = value

    if sect_pr is not None:
        index = list(body).index(sect_pr)
        body.insert(index, p)
    else:
        body.append(p)

# Leerzeile
add_paragraph("")

# Überschrift
add_paragraph(marker, bold=True, style="Heading2")

add_paragraph(
    "Für die Live-Demonstration wurde der finale dokumentierte "
    "GitOps- und Kubernetes-Betriebszustand überprüft. "
    "Die laufenden Workloads wurden mit den in Git versionierten "
    "Sollständen abgeglichen."
)

add_paragraph("Finale Git-Stände", bold=True)

add_label_value(
    "pacman-app Commit",
    app_commit
)

add_label_value(
    "pacman-gitops Commit",
    gitops_commit
)

add_paragraph("Argo-CD-Zustand", bold=True)

add_label_value(
    "pacman-dev",
    "Synced / Healthy"
)

add_label_value(
    "pacman-prod",
    "Synced / Healthy"
)

add_paragraph("Entwicklungsumgebung", bold=True)

add_label_value(
    "Pacman Deployment",
    "1/1 verfügbar"
)

add_label_value(
    "MongoDB StatefulSet",
    "1/1 verfügbar"
)

add_label_value(
    "Persistenz",
    "MongoDB-Daten-PVC und Backup-PVC jeweils Bound"
)

add_label_value(
    "Horizontal Pod Autoscaler",
    "1 bis 3 Pacman-Replikate"
)

add_label_value(
    "Image",
    dev_image
)

add_label_value(
    "Image Digest",
    dev_digest
)

add_paragraph("Produktionsumgebung", bold=True)

add_label_value(
    "Pacman Deployment",
    "3/3 verfügbar"
)

add_label_value(
    "MongoDB StatefulSet",
    "1/1 verfügbar"
)

add_label_value(
    "Persistenz",
    "MongoDB-Daten-PVC und Backup-PVC jeweils Bound"
)

add_label_value(
    "Horizontal Pod Autoscaler",
    "3 bis 6 Pacman-Replikate"
)

add_label_value(
    "Image",
    prod_image
)

add_label_value(
    "Image Digest",
    prod_digest
)

add_paragraph("Backup und Restore", bold=True)

add_paragraph(
    "Mehrere geplante MongoDB-Backup-Jobs wurden erfolgreich "
    "abgeschlossen. Der manuelle Restore-Test wurde erfolgreich "
    "durchgeführt. Nach einem vorübergehend fehlgeschlagenen "
    "Produktions-Backup wurde im Rahmen von AP33 ein kontrollierter "
    "Nachtest aus demselben CronJob-Template gestartet. "
    "Der Nachtest wurde mit Complete 1/1 erfolgreich abgeschlossen."
)

add_paragraph("Ergebnis", bold=True)

add_paragraph(
    "Der Kubernetes-Istzustand entspricht dem im finalen GitOps-Stand "
    "definierten Sollzustand. Dev und Prod verwenden jeweils die in "
    "ihren GitOps-Overlays definierten Image-Versionen. "
    "Die Image-Digests bestätigen die tatsächlich ausgeführten "
    "Container-Images. Zum Zeitpunkt des Abschlussnachweises meldete "
    "Argo CD beide Applications als Synced und Healthy."
)

new_xml = ET.tostring(
    root,
    encoding="utf-8",
    xml_declaration=True
)

fd, temp_path = tempfile.mkstemp(suffix=".docx")
os.close(fd)

try:
    with zipfile.ZipFile(docx, "r") as zin, \
         zipfile.ZipFile(temp_path, "w") as zout:

        for item in zin.infolist():
            data = zin.read(item.filename)

            if item.filename == "word/document.xml":
                data = new_xml

            zout.writestr(item, data)

    shutil.move(temp_path, docx)

finally:
    if os.path.exists(temp_path):
        os.remove(temp_path)

print("OK: AP33-Abschnitt wurde ergänzt.")
PY

echo
echo "4. DOCX-Struktur nach Änderung prüfen ..."

if ! unzip -t "$DOCX" >/dev/null 2>&1; then
    echo "FEHLER: DOCX-Struktur nach Änderung ungültig."
    echo
    echo "Backup wiederherstellen mit:"
    echo "cp '$BACKUP' '$DOCX'"
    exit 4
fi

echo "OK: DOCX-Struktur weiterhin gültig."

echo
echo "5. Inhalt prüfen ..."

TEXT="$(
    unzip -p "$DOCX" word/document.xml 2>/dev/null \
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

check_value "AP33-Abschnitt" "$MARKER"
check_value "pacman-app Commit" "$APP_COMMIT"
check_value "pacman-gitops Commit" "$GITOPS_COMMIT"
check_value "Dev Image" "$DEV_IMAGE"
check_value "Dev Digest" "$DEV_DIGEST"
check_value "Prod Image" "$PROD_IMAGE"
check_value "Prod Digest" "$PROD_DIGEST"

echo

if [[ "$CHECK_FAILED" -eq 0 ]]; then
    echo "============================================================"
    echo " AP33-Dokumentation erfolgreich aktualisiert"
    echo "============================================================"
    echo
    echo "Dokument:"
    echo "$DOCX"
    echo
    echo "Backup:"
    echo "$BACKUP"
else
    echo "FEHLER: Mindestens ein AP33-Wert fehlt im Dokument."
    exit 5
fi