#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Grafana Health Check für das Pacman-/Kubernetes-Projekt
# - verändert keine Kubernetes-Ressourcen
# - gibt keine Secret-Werte aus
# - prüft Pod, Deployment, Service, Endpoints, Persistenz,
#   Dashboards und Grafana HTTP Health API
# ============================================================

NAMESPACE="${NAMESPACE:-monitoring}"
GRAFANA_SERVICE="${GRAFANA_SERVICE:-monitoring-grafana}"
LOCAL_PORT="${GRAFANA_LOCAL_PORT:-13000}"

ERRORS=0
WARNINGS=0
PF_PID=""
PF_LOG=""

ok() {
    echo "[OK]   $*"
}

warn() {
    echo "[WARN] $*"
    WARNINGS=$((WARNINGS + 1))
}

error() {
    echo "[FEHLER] $*"
    ERRORS=$((ERRORS + 1))
}

info() {
    echo "[INFO] $*"
}

cleanup() {
    if [[ -n "${PF_PID}" ]] && kill -0 "${PF_PID}" 2>/dev/null; then
        kill "${PF_PID}" 2>/dev/null || true
        wait "${PF_PID}" 2>/dev/null || true
    fi

    if [[ -n "${PF_LOG}" && -f "${PF_LOG}" ]]; then
        rm -f "${PF_LOG}"
    fi
}

trap cleanup EXIT

echo
echo "============================================================"
echo " Grafana Check"
echo " Namespace: ${NAMESPACE}"
echo "============================================================"
echo

# ------------------------------------------------------------
# 1. kubectl vorhanden?
# ------------------------------------------------------------

echo "1. Kubernetes-Zugriff"

if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl ist nicht installiert oder nicht im PATH."
    exit 2
fi

ok "kubectl ist vorhanden."

if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    ok "Namespace '${NAMESPACE}' ist erreichbar."
else
    error "Namespace '${NAMESPACE}' wurde nicht gefunden."
    exit 1
fi

CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

if [[ -n "${CONTEXT}" ]]; then
    info "Aktueller Kubernetes-Kontext: ${CONTEXT}"
else
    warn "Aktueller Kubernetes-Kontext konnte nicht ermittelt werden."
fi

echo

# ------------------------------------------------------------
# 2. Grafana Pod finden
# ------------------------------------------------------------

echo "2. Grafana Pod"

POD="$(
    kubectl get pods \
        -n "${NAMESPACE}" \
        -l app.kubernetes.io/name=grafana \
        -o jsonpath='{.items[0].metadata.name}' \
        2>/dev/null || true
)"

# Fallback, falls das Label nicht vorhanden ist
if [[ -z "${POD}" ]]; then
    POD="$(
        kubectl get pods -n "${NAMESPACE}" \
            --no-headers 2>/dev/null |
        awk 'tolower($1) ~ /grafana/ {print $1; exit}'
    )"
fi

if [[ -z "${POD}" ]]; then
    error "Kein Grafana-Pod gefunden."
else
    ok "Grafana-Pod gefunden: ${POD}"

    PHASE="$(
        kubectl get pod "${POD}" \
            -n "${NAMESPACE}" \
            -o jsonpath='{.status.phase}'
    )"

    if [[ "${PHASE}" == "Running" ]]; then
        ok "Pod-Status: Running"
    else
        error "Pod-Status ist '${PHASE}', erwartet wurde 'Running'."
    fi

    READY="$(
        kubectl get pod "${POD}" \
            -n "${NAMESPACE}" \
            -o jsonpath='{range .status.containerStatuses[*]}{.ready}{"\n"}{end}' |
        grep -c '^true$' || true
    )"

    TOTAL="$(
        kubectl get pod "${POD}" \
            -n "${NAMESPACE}" \
            -o jsonpath='{.status.containerStatuses[*].name}' |
        wc -w
    )"

    if [[ "${READY}" -eq "${TOTAL}" && "${TOTAL}" -gt 0 ]]; then
        ok "Container Ready: ${READY}/${TOTAL}"
    else
        error "Nicht alle Container sind Ready: ${READY}/${TOTAL}"
    fi

    RESTARTS="$(
        kubectl get pod "${POD}" \
            -n "${NAMESPACE}" \
            -o jsonpath='{range .status.containerStatuses[*]}{.restartCount}{"\n"}{end}' |
        awk '{sum += $1} END {print sum+0}'
    )"

    if [[ "${RESTARTS}" -eq 0 ]]; then
        ok "Keine Container-Restarts."
    else
        warn "Container-Restarts insgesamt: ${RESTARTS}"
    fi
fi

echo

# ------------------------------------------------------------
# 3. Grafana Deployment
# ------------------------------------------------------------

echo "3. Grafana Deployment"

DEPLOYMENT="$(
    kubectl get deployment \
        -n "${NAMESPACE}" \
        -l app.kubernetes.io/name=grafana \
        -o jsonpath='{.items[0].metadata.name}' \
        2>/dev/null || true
)"

if [[ -z "${DEPLOYMENT}" ]]; then
    DEPLOYMENT="$(
        kubectl get deployment -n "${NAMESPACE}" \
            --no-headers 2>/dev/null |
        awk 'tolower($1) ~ /grafana/ {print $1; exit}'
    )"
fi

if [[ -n "${DEPLOYMENT}" ]]; then
    ok "Deployment gefunden: ${DEPLOYMENT}"

    if kubectl rollout status \
        deployment/"${DEPLOYMENT}" \
        -n "${NAMESPACE}" \
        --timeout=10s >/dev/null 2>&1; then

        ok "Grafana Deployment erfolgreich ausgerollt."
    else
        error "Grafana Deployment ist nicht vollständig verfügbar."
    fi
else
    warn "Kein Grafana-Deployment gefunden."
fi

echo

# ------------------------------------------------------------
# 4. Grafana Service
# ------------------------------------------------------------

echo "4. Grafana Service"

if ! kubectl get service "${GRAFANA_SERVICE}" \
    -n "${NAMESPACE}" >/dev/null 2>&1; then

    warn "Service '${GRAFANA_SERVICE}' wurde nicht gefunden."

    GRAFANA_SERVICE="$(
        kubectl get svc -n "${NAMESPACE}" \
            --no-headers |
        awk 'tolower($1) ~ /grafana/ {print $1; exit}'
    )"
fi

if [[ -n "${GRAFANA_SERVICE}" ]]; then
    ok "Grafana-Service: ${GRAFANA_SERVICE}"

    SERVICE_PORT="$(
        kubectl get svc "${GRAFANA_SERVICE}" \
            -n "${NAMESPACE}" \
            -o jsonpath='{.spec.ports[0].port}'
    )"

    SERVICE_TYPE="$(
        kubectl get svc "${GRAFANA_SERVICE}" \
            -n "${NAMESPACE}" \
            -o jsonpath='{.spec.type}'
    )"

    info "Service-Typ: ${SERVICE_TYPE}"
    info "Service-Port: ${SERVICE_PORT}"
else
    error "Kein Grafana-Service gefunden."
    SERVICE_PORT=""
fi

echo

# ------------------------------------------------------------
# 5. Service Endpoints prüfen
# ------------------------------------------------------------

echo "5. Grafana Endpoints"

if [[ -n "${GRAFANA_SERVICE}" ]]; then

    ENDPOINTS="$(
        kubectl get endpointslice \
            -n "${NAMESPACE}" \
            -l "kubernetes.io/service-name=${GRAFANA_SERVICE}" \
            -o jsonpath='{range .items[*].endpoints[*].addresses[*]}{.}{" "}{end}' \
            2>/dev/null || true
    )"

    if [[ -n "${ENDPOINTS}" ]]; then
        ok "Service besitzt erreichbare Endpoint(s): ${ENDPOINTS}"
    else
        error "Der Grafana-Service besitzt keine Endpoint-Adresse."
    fi
fi

echo

# ------------------------------------------------------------
# 6. Grafana Persistenz prüfen
# ------------------------------------------------------------

echo "6. Grafana Persistenz"

PVC_COUNT="$(
    kubectl get pvc -n "${NAMESPACE}" \
        --no-headers 2>/dev/null |
    wc -l
)"

if [[ "${PVC_COUNT}" -eq 0 ]]; then
    warn "Im Namespace '${NAMESPACE}' existiert kein PVC."
else
    ok "${PVC_COUNT} PVC(s) im Namespace vorhanden."
fi

if [[ -n "${POD}" ]]; then

    STORAGE_VOLUME="$(
        kubectl get pod "${POD}" \
            -n "${NAMESPACE}" \
            -o jsonpath='{range .spec.containers[?(@.name=="grafana")].volumeMounts[?(@.mountPath=="/var/lib/grafana")]}{.name}{end}' \
            2>/dev/null || true
    )"

    if [[ -n "${STORAGE_VOLUME}" ]]; then

        info "/var/lib/grafana verwendet Volume: ${STORAGE_VOLUME}"

        VOLUME_INFO="$(
            kubectl get pod "${POD}" \
                -n "${NAMESPACE}" \
                -o jsonpath='{range .spec.volumes[*]}{.name}{"|"}{.persistentVolumeClaim.claimName}{"|"}{.emptyDir}{"\n"}{end}' |
            awk -F'|' -v volume="${STORAGE_VOLUME}" '$1 == volume {print; exit}'
        )"

        PVC_NAME="$(echo "${VOLUME_INFO}" | cut -d'|' -f2)"
        EMPTYDIR="$(echo "${VOLUME_INFO}" | cut -d'|' -f3)"

        if [[ -n "${PVC_NAME}" ]]; then
            ok "/var/lib/grafana ist persistent über PVC '${PVC_NAME}'."
        elif [[ -n "${EMPTYDIR}" ]]; then
            warn "/var/lib/grafana verwendet emptyDir."
            warn "Manuell gespeicherte Grafana-Daten können bei Pod-Neuerstellung verloren gehen."
        else
            warn "Speichertyp für /var/lib/grafana konnte nicht eindeutig bestimmt werden."
        fi

    else
        warn "Kein Mount für /var/lib/grafana gefunden."
    fi
fi

echo

# ------------------------------------------------------------
# 7. Provisionierte Dashboards
# ------------------------------------------------------------

echo "7. Provisionierte Dashboards"

DASHBOARD_COUNT="$(
    kubectl get configmap \
        -n "${NAMESPACE}" \
        -l grafana_dashboard=1 \
        --no-headers 2>/dev/null |
    wc -l
)"

if [[ "${DASHBOARD_COUNT}" -gt 0 ]]; then
    ok "${DASHBOARD_COUNT} Dashboard-ConfigMap(s) gefunden."
else
    warn "Keine ConfigMaps mit Label grafana_dashboard=1 gefunden."
fi

PACMAN_DASHBOARDS="$(
    kubectl get configmap \
        -n "${NAMESPACE}" \
        -l grafana_dashboard=1 \
        --no-headers 2>/dev/null |
    awk 'tolower($1) ~ /pacman/ {print $1}' || true
)"

if [[ -n "${PACMAN_DASHBOARDS}" ]]; then
    ok "Pacman-Dashboard gefunden:"
    echo "${PACMAN_DASHBOARDS}" | sed 's/^/       - /'
else
    warn "Kein Pacman-spezifisches Dashboard als ConfigMap gefunden."
fi

echo

# ------------------------------------------------------------
# 8. Grafana Secret prüfen
#    KEINE Secret-Werte ausgeben!
# ------------------------------------------------------------

echo "8. Grafana Zugangsdaten-Konfiguration"

if kubectl get secret "${GRAFANA_SERVICE}" \
    -n "${NAMESPACE}" >/dev/null 2>&1; then

    ADMIN_USER="$(
        kubectl get secret "${GRAFANA_SERVICE}" \
            -n "${NAMESPACE}" \
            -o jsonpath='{.data.admin-user}' 2>/dev/null || true
    )"

    ADMIN_PASSWORD="$(
        kubectl get secret "${GRAFANA_SERVICE}" \
            -n "${NAMESPACE}" \
            -o jsonpath='{.data.admin-password}' 2>/dev/null || true
    )"

    if [[ -n "${ADMIN_USER}" ]]; then
        ok "Secret enthält 'admin-user'."
    else
        warn "Secret enthält keinen Schlüssel 'admin-user'."
    fi

    if [[ -n "${ADMIN_PASSWORD}" ]]; then
        ok "Secret enthält 'admin-password'."
    else
        warn "Secret enthält keinen Schlüssel 'admin-password'."
    fi

    info "Secret-Werte werden aus Sicherheitsgründen nicht ausgegeben."
else
    warn "Grafana-Secret '${GRAFANA_SERVICE}' wurde nicht gefunden."
fi

echo

# ------------------------------------------------------------
# 9. Grafana HTTP API Health Check
# ------------------------------------------------------------

echo "9. Grafana HTTP Health Check"

if ! command -v curl >/dev/null 2>&1; then
    warn "curl ist nicht installiert. HTTP-Test wird übersprungen."

elif [[ -z "${SERVICE_PORT}" ]]; then
    warn "Kein Service-Port verfügbar. HTTP-Test wird übersprungen."

else

    PF_LOG="$(mktemp)"

    kubectl port-forward \
        -n "${NAMESPACE}" \
        "svc/${GRAFANA_SERVICE}" \
        "${LOCAL_PORT}:${SERVICE_PORT}" \
        >"${PF_LOG}" 2>&1 &

    PF_PID=$!

    HEALTH_RESPONSE=""

    for i in {1..10}; do

        if HEALTH_RESPONSE="$(
            curl \
                --silent \
                --show-error \
                --fail \
                --max-time 2 \
                "http://127.0.0.1:${LOCAL_PORT}/api/health" \
                2>/dev/null
        )"; then
            break
        fi

        sleep 1
    done

    if [[ -n "${HEALTH_RESPONSE}" ]]; then

        ok "Grafana HTTP API ist erreichbar."

        if echo "${HEALTH_RESPONSE}" |
            grep -Eq '"database"[[:space:]]*:[[:space:]]*"ok"'; then

            ok "Grafana-Datenbankstatus: OK"
        else
            warn "Grafana antwortet, aber Datenbankstatus ist nicht eindeutig OK."
        fi

        info "Health Response:"
        echo "${HEALTH_RESPONSE}" | sed 's/^/       /'

    else
        error "Grafana /api/health ist über Port-Forward nicht erreichbar."

        if [[ -f "${PF_LOG}" ]]; then
            echo "       Port-Forward-Ausgabe:"
            sed 's/^/       /' "${PF_LOG}"
        fi
    fi
fi

echo

# ------------------------------------------------------------
# Zusammenfassung
# ------------------------------------------------------------

echo "============================================================"
echo " Ergebnis"
echo "============================================================"
echo " Fehler   : ${ERRORS}"
echo " Warnungen: ${WARNINGS}"
echo

if [[ "${ERRORS}" -eq 0 ]]; then
    echo "[OK] Grafana ist grundsätzlich betriebsbereit."

    if [[ "${WARNINGS}" -gt 0 ]]; then
        echo "[INFO] Es bestehen jedoch Warnungen bzw. betriebliche Einschränkungen."
    fi

    exit 0
else
    echo "[FEHLER] Grafana-Check hat kritische Fehler gefunden."
    exit 1
fi