#!/usr/bin/env bash
#
# ap27-actions-pruefung.sh
# AP27 - Prüfung verbindlicher Anforderungen an GitHub Actions und Skripte
#
# Das Skript führt ausschließlich statische Prüfungen durch.
# Es verändert keine Workflows, Skripte oder Kubernetes-Ressourcen.
#

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_REPO="${PROJECT_ROOT}/pacman-app"
GITOPS_REPO="${PROJECT_ROOT}/pacman-gitops"

WORKFLOW_DIRS=(
  "${APP_REPO}/.github/workflows"
  "${GITOPS_REPO}/.github/workflows"
)

SCRIPT_DIRS=(
  "${APP_REPO}/scripts"
  "${GITOPS_REPO}/scripts"
)

section() {
  echo
  echo "================================================================"
  echo "$1"
  echo "================================================================"
}

locations_only() {
  cut -d: -f1-2 | sort -u
}

echo "=== AP27 GitHub-Actions- und Skriptprüfung ==="
echo "Projekt: ${PROJECT_ROOT}"
echo "Zeitpunkt: $(date '+%Y-%m-%d %H:%M:%S')"

# ------------------------------------------------------------------
# 1. Workflows und Skripte
# ------------------------------------------------------------------

section "1. Vorhandene Workflows und Skripte"

echo "--- GitHub-Actions-Workflows ---"
find "${WORKFLOW_DIRS[@]}" \
  -maxdepth 1 \
  -type f \
  \( -name '*.yml' -o -name '*.yaml' \) \
  -print 2>/dev/null || true

echo
echo "--- Shell-Skripte ---"
find "${SCRIPT_DIRS[@]}" \
  -maxdepth 1 \
  -type f \
  -name '*.sh' \
  -print 2>/dev/null || true

echo
echo "HINWEIS:"
echo "Benennung, Kommentare und Zweck müssen anschließend fachlich bewertet werden."

# ------------------------------------------------------------------
# 2. Secrets
# ------------------------------------------------------------------

section "2. Secret-Verwendung"

echo "--- Verweise auf GitHub Actions Secrets ---"
grep -RInE \
  'secrets\.|GITHUB_TOKEN' \
  "${WORKFLOW_DIRS[@]}" 2>/dev/null \
  | locations_only || true

echo
echo "--- Verweise auf Kubernetes Secrets / verdeckte Eingaben ---"
grep -RInE \
  'secretKeyRef|read[[:space:]]+-[^[:space:]]*s' \
  "${SCRIPT_DIRS[@]}" "${GITOPS_REPO}" 2>/dev/null \
  | locations_only || true

echo
echo "Es werden nur Fundstellen ausgegeben, keine Secret-Werte."

# ------------------------------------------------------------------
# 3. Gefährliche Log-Ausgaben
# ------------------------------------------------------------------

section "3. Prüfung auf potenziell sensible Log-Ausgaben"

SENSITIVE_LOG_MATCHES="$(
  grep -RInE \
    'set -x|printenv|kubectl config view.*--raw|kubectl get secret.*-o (yaml|json)|cat .*kube/config' \
    "${WORKFLOW_DIRS[@]}" "${SCRIPT_DIRS[@]}" 2>/dev/null \
    | locations_only || true
)"

if [[ -z "${SENSITIVE_LOG_MATCHES}" ]]; then
  echo "[OK] Keine offensichtlich gefährlichen Log-Ausgaben gefunden."
else
  echo "[PRÜFEN] Potenziell kritische Fundstellen:"
  echo "${SENSITIVE_LOG_MATCHES}"
fi

# ------------------------------------------------------------------
# 4. Fehlerbehandlung / Exit Codes
# ------------------------------------------------------------------

section "4. Fehlerbehandlung und Exit Codes"

for dir in "${SCRIPT_DIRS[@]}"; do
  [[ -d "${dir}" ]] || continue

  while IFS= read -r script; do
    echo
    echo "--- ${script} ---"

    if bash -n "${script}"; then
      echo "[OK] Bash-Syntax korrekt"
    else
      echo "[FEHLER] Bash-Syntax fehlerhaft"
    fi

    if grep -qE 'exit[[:space:]]+[0-9]+' "${script}"; then
      echo "[OK] Explizite Exit Codes vorhanden"
    else
      echo "[PRÜFEN] Keine expliziten Exit Codes erkannt"
    fi

    if grep -qE '\-\-help|-h|usage\(\)' "${script}"; then
      echo "[OK] Hilfe-/Usage-Logik erkannt"
    else
      echo "[PRÜFEN] Keine Hilfeoption erkannt"
    fi

  done < <(find "${dir}" -maxdepth 1 -type f -name '*.sh' -print)
done

# ------------------------------------------------------------------
# 5. Gefährliche Aktionen
# ------------------------------------------------------------------

section "5. Lösch-, Restore- und Rollback-Aktionen"

DANGEROUS_ACTIONS="$(
  grep -RInE \
    'kubectl delete|kubectl rollout undo|mongorestore|restore|rollback|rm -rf' \
    "${WORKFLOW_DIRS[@]}" "${SCRIPT_DIRS[@]}" 2>/dev/null \
    | locations_only || true
)"

if [[ -z "${DANGEROUS_ACTIONS}" ]]; then
  echo "[OK] Keine entsprechenden Aktionen gefunden."
else
  echo "[PRÜFEN] Gefährliche Aktionen gefunden:"
  echo "${DANGEROUS_ACTIONS}"
  echo
  echo "Diese Stellen müssen einen klaren manuellen Trigger"
  echo "oder eine ausdrückliche Bestätigung besitzen."
fi

# ------------------------------------------------------------------
# 6. GitHub Actions Versionen und Permissions
# ------------------------------------------------------------------

section "6. GitHub Actions Versionen und Permissions"

echo "--- Verwendete Actions ---"
grep -RInE \
  '^[[:space:]]*-[[:space:]]*uses:|^[[:space:]]*uses:' \
  "${WORKFLOW_DIRS[@]}" 2>/dev/null || true

echo
echo "--- Permissions ---"
grep -RInE \
  '^[[:space:]]*permissions:|^[[:space:]]*(contents|packages|actions|pull-requests):|write-all' \
  "${WORKFLOW_DIRS[@]}" 2>/dev/null || true

echo
echo "--- Prüfung auf write-all ---"

if grep -RqE 'permissions:[[:space:]]*write-all|write-all' \
  "${WORKFLOW_DIRS[@]}" 2>/dev/null; then
  echo "[PRÜFEN] 'write-all' gefunden. Least-Privilege prüfen."
else
  echo "[OK] Kein 'write-all' gefunden."
fi

# ------------------------------------------------------------------
# 7. continue-on-error
# ------------------------------------------------------------------

section "7. continue-on-error"

CONTINUE_MATCHES="$(
  grep -RIn \
    'continue-on-error' \
    "${WORKFLOW_DIRS[@]}" 2>/dev/null || true
)"

if [[ -z "${CONTINUE_MATCHES}" ]]; then
  echo "[OK] Kein continue-on-error gefunden."
else
  echo "${CONTINUE_MATCHES}"
  echo
  echo "[PRÜFEN] Für jeden Treffer bewerten, ob der Schritt"
  echo "für Build, Test oder Freigabe relevant ist."
fi

# ------------------------------------------------------------------
# 8. Direkter Clusterzugriff aus GitHub Actions
# ------------------------------------------------------------------

section "8. Direkter Kubernetes-Clusterzugriff aus GitHub Actions"

DIRECT_CLUSTER_ACCESS="$(
  grep -RInE \
    'kubectl[[:space:]]+(apply|create|delete|patch|scale|set|rollout)|KUBECONFIG|docker-desktop|kubectl config use-context' \
    "${WORKFLOW_DIRS[@]}" 2>/dev/null \
    | locations_only || true
)"

if [[ -z "${DIRECT_CLUSTER_ACCESS}" ]]; then
  echo "[OK] Kein offensichtlicher direkter Deployment-Zugriff gefunden."
  echo "[OK] GitOps-Bereitstellung über Git und Argo CD ist damit statisch plausibel."
else
  echo "[PRÜFEN] Möglicher direkter Clusterzugriff gefunden:"
  echo "${DIRECT_CLUSTER_ACCESS}"
fi

section "AP27 Prüfung abgeschlossen"

echo "Die Prüfung verändert keine Dateien oder Cluster-Ressourcen."
echo
echo "Wichtig:"
echo "Treffer mit [PRÜFEN] sind manuell fachlich zu bewerten."
echo "Nicht jeder Treffer stellt automatisch einen AP27-Verstoß dar."

exit 0