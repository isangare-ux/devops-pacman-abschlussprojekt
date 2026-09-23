
#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="apps/pacman/base"
PROD_DIR="apps/pacman/overlays/prod"

BASE_KUSTOMIZATION="$BASE_DIR/kustomization.yaml"
BASE_PDB="$BASE_DIR/pdb.yaml"

PROD_KUSTOMIZATION="$PROD_DIR/kustomization.yaml"
PROD_PDB="$PROD_DIR/pdb.yaml"

EXPECTED_ORIGIN="f051d6087d7f0437b852c21f2045122f42ab1c22"

echo "=================================================="
echo " PDB nur für pacman-prod bereitstellen"
echo "=================================================="
echo

# --------------------------------------------------
# 1. Git-Zustand prüfen
# --------------------------------------------------

echo "1. Git-Zustand prüfen ..."

git fetch origin >/dev/null

HEAD="$(git rev-parse HEAD)"
ORIGIN="$(git rev-parse origin/main)"

echo "HEAD:        $HEAD"
echo "origin/main: $ORIGIN"

if [[ -n "$(git status --porcelain)" ]]; then
    echo
    echo "ABBRUCH: Working Tree ist nicht sauber."
    git status --short
    exit 1
fi

if [[ "$HEAD" != "$ORIGIN" ]]; then
    echo
    echo "ABBRUCH: Lokaler Stand entspricht nicht origin/main."
    echo "Bitte zuerst ausführen:"
    echo
    echo "git pull --ff-only origin main"
    exit 2
fi

if [[ "$ORIGIN" != "$EXPECTED_ORIGIN" ]]; then
    echo
    echo "WARNUNG:"
    echo "origin/main entspricht nicht mehr dem zuletzt dokumentierten GitOps-Commit."
    echo "Erwartet: $EXPECTED_ORIGIN"
    echo "Aktuell:   $ORIGIN"
    echo
    echo "Keine Änderung durchgeführt."
    exit 3
fi

echo "OK: Lokaler Git-Stand entspricht dem dokumentierten origin/main."

# --------------------------------------------------
# 2. Dateien prüfen
# --------------------------------------------------

echo
echo "2. PDB-Dateien prüfen ..."

for FILE in \
    "$BASE_KUSTOMIZATION" \
    "$BASE_PDB" \
    "$PROD_KUSTOMIZATION"
do
    if [[ ! -f "$FILE" ]]; then
        echo "FEHLER: Datei fehlt: $FILE"
        exit 4
    fi
done

if ! grep -qE '^[[:space:]]*-[[:space:]]+pdb\.yaml[[:space:]]*$' \
    "$BASE_KUSTOMIZATION"; then
    echo "FEHLER: pdb.yaml ist nicht in der Base-Kustomization eingetragen."
    exit 5
fi

if ! grep -qE '^[[:space:]]*minAvailable:[[:space:]]*2[[:space:]]*$' \
    "$BASE_PDB"; then
    echo "FEHLER: Erwartetes minAvailable: 2 wurde nicht gefunden."
    exit 6
fi

echo "OK: Ausgangszustand erkannt."

# --------------------------------------------------
# 3. PDB nach Prod verschieben
# --------------------------------------------------

echo
echo "3. pdb.yaml aus Base nach Prod verschieben ..."

mv "$BASE_PDB" "$PROD_PDB"

echo "OK: $PROD_PDB"

# --------------------------------------------------
# 4. Base-Kustomization bereinigen
# --------------------------------------------------

echo
echo "4. pdb.yaml aus Base-Ressourcen entfernen ..."

sed -i \
    '/^[[:space:]]*-[[:space:]]*pdb\.yaml[[:space:]]*$/d' \
    "$BASE_KUSTOMIZATION"

echo "OK."

# --------------------------------------------------
# 5. Prod-Kustomization ergänzen
# --------------------------------------------------

echo
echo "5. pdb.yaml in Prod-resources eintragen ..."

if grep -qE '^[[:space:]]*-[[:space:]]*pdb\.yaml[[:space:]]*$' \
    "$PROD_KUSTOMIZATION"; then

    echo "INFO: pdb.yaml ist bereits im Prod-Overlay eingetragen."

else
    # Direkt nach ../../base einfügen.
    sed -i \
        '/^[[:space:]]*-[[:space:]]*\.\.\/\.\.\/base[[:space:]]*$/a\  - pdb.yaml' \
        "$PROD_KUSTOMIZATION"

    echo "OK: pdb.yaml wurde zu Prod-resources hinzugefügt."
fi

# --------------------------------------------------
# 6. Dev und Prod rendern
# --------------------------------------------------

DEV_RENDER="$(mktemp)"
PROD_RENDER="$(mktemp)"

trap 'rm -f "$DEV_RENDER" "$PROD_RENDER"' EXIT

echo
echo "6. Dev rendern ..."

kubectl kustomize apps/pacman/overlays/dev > "$DEV_RENDER"

echo "OK."

echo
echo "7. Prod rendern ..."

kubectl kustomize apps/pacman/overlays/prod > "$PROD_RENDER"

echo "OK."

# --------------------------------------------------
# 7. Erwarteten Zustand prüfen
# --------------------------------------------------

echo
echo "8. PDB-Zielzustand prüfen ..."

DEV_PDB_COUNT="$(
    grep -c '^kind: PodDisruptionBudget$' "$DEV_RENDER" || true
)"

PROD_PDB_COUNT="$(
    grep -c '^kind: PodDisruptionBudget$' "$PROD_RENDER" || true
)"

echo "Dev PDB-Anzahl:  $DEV_PDB_COUNT"
echo "Prod PDB-Anzahl: $PROD_PDB_COUNT"

if [[ "$DEV_PDB_COUNT" -ne 0 ]]; then
    echo "FEHLER: Dev enthält weiterhin einen PDB."
    exit 7
fi

if [[ "$PROD_PDB_COUNT" -ne 1 ]]; then
    echo "FEHLER: Prod muss genau einen PDB enthalten."
    exit 8
fi

PROD_MIN="$(
    awk '
        /^kind: PodDisruptionBudget$/ {pdb=1; next}
        pdb && /^---$/ {pdb=0}
        pdb && /^[[:space:]]*minAvailable:/ {
            print $2
            exit
        }
    ' "$PROD_RENDER"
)"

echo "Prod minAvailable: $PROD_MIN"

if [[ "$PROD_MIN" != "2" ]]; then
    echo "FEHLER: Prod-PDB muss minAvailable: 2 verwenden."
    exit 9
fi

echo
echo "OK:"
echo "DEV  -> kein PodDisruptionBudget"
echo "PROD -> PodDisruptionBudget minAvailable: 2"

# --------------------------------------------------
# 8. Dry Run
# --------------------------------------------------

echo
echo "9. Client-Dry-Run Dev ..."

kubectl apply \
    --dry-run=client \
    -f "$DEV_RENDER" \
    >/dev/null

echo "OK."

echo
echo "10. Client-Dry-Run Prod ..."

kubectl apply \
    --dry-run=client \
    -f "$PROD_RENDER" \
    >/dev/null

echo "OK."

# --------------------------------------------------
# 9. Git-Diff
# --------------------------------------------------

echo
echo "=================================================="
echo " Änderung vorbereitet – noch nicht committed"
echo "=================================================="

git status --short

echo
echo "Git Diff:"
git diff -- \
    "$BASE_KUSTOMIZATION" \
    "$PROD_KUSTOMIZATION" \
    "$PROD_PDB"

echo
echo "Noch KEIN Commit, KEIN Push und KEIN kubectl apply."