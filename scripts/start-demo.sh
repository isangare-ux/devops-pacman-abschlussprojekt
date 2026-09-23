#!/usr/bin/env bash
#
# start-demo.sh
#
# Prüft die Pacman-Umgebung (Kontext, Argo CD, Namespaces, Services,
# Dev-/Prod-Replikate), startet die Port-Forwards für Pacman Dev/Prod,
# Prometheus, Grafana und Argo CD und zeigt danach den Kubernetes-
# Zustand live an. Führt kein kubectl apply/scale aus (siehe --help).
#
# Verwendung:
#   ./scripts/start-demo.sh [--help]
#
set -Eeuo pipefail

EXPECTED_CONTEXT="docker-desktop"

DEV_NAMESPACE="pacman-dev"
PROD_NAMESPACE="pacman-prod"
MONITORING_NAMESPACE="monitoring"
ARGOCD_NAMESPACE="argocd"

PACMAN_DEPLOYMENT="pacman"
PACMAN_SERVICE="pacman"
MONGODB_STATEFULSET="mongodb"
MONGODB_SERVICE="mongodb"

PROMETHEUS_SERVICE="prometheus-operated"
GRAFANA_SERVICE="monitoring-grafana"
ARGOCD_SERVICE="argocd-server"

PROMETHEUS_LOCAL_PORT="9090"
GRAFANA_LOCAL_PORT="3000"
ARGOCD_LOCAL_PORT="8443"
PACMAN_DEV_LOCAL_PORT="8081"
PACMAN_PROD_LOCAL_PORT="8082"

PROMETHEUS_PORT="${PROMETHEUS_LOCAL_PORT}:9090"
GRAFANA_PORT="${GRAFANA_LOCAL_PORT}:80"
ARGOCD_PORT="${ARGOCD_LOCAL_PORT}:443"
PACMAN_DEV_PORT="${PACMAN_DEV_LOCAL_PORT}:80"
PACMAN_PROD_PORT="${PACMAN_PROD_LOCAL_PORT}:80"

LIVE_INTERVAL=5

LOG_DIR="${HOME}/pacman-portforward-logs"
PID_DIR="${HOME}/pacman-portforward-pids"

mkdir -p "$LOG_DIR" "$PID_DIR"

show_help() {
    cat <<EOF
Verwendung:
  $0

Zweck:
  Prüft die Pacman-Umgebung, startet Port-Forwards und zeigt den
  Kubernetes-Zustand anschließend live an.

Port-Forwards:
  Pacman Dev -> http://localhost:${PACMAN_DEV_LOCAL_PORT}
  Pacman Prod -> http://localhost:${PACMAN_PROD_LOCAL_PORT}
  Prometheus -> http://localhost:${PROMETHEUS_LOCAL_PORT}
  Grafana    -> http://localhost:${GRAFANA_LOCAL_PORT}
  Argo CD    -> https://localhost:${ARGOCD_LOCAL_PORT}

CTRL+C beendet nur die Live-Anzeige.
Die Port-Forwards bleiben aktiv.

Port-Forwards beenden:
  ./scripts/stop-demo.sh

Hinweis:
  Das Skript führt kein kubectl apply und kein kubectl scale aus.
  Git / Argo CD bleiben die Quelle des Sollzustands.
EOF
}

case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    "")
        ;;
    *)
        echo "FEHLER: Unbekannter Parameter: $1"
        echo "Verwende: $0 --help"
        exit 2
        ;;
esac

error() {
    echo "FEHLER: $*" >&2
}

warning() {
    echo "WARNUNG: $*" >&2
}

info() {
    echo "INFO: $*"
}

require_command() {
    local command_name="$1"
    if ! command -v "$command_name" >/dev/null 2>&1; then
        error "Erforderlicher Befehl '$command_name' wurde nicht gefunden."
        exit 1
    fi
}

require_cluster_reachable() {
    if ! kubectl get nodes >/dev/null 2>&1; then
        error "Kubernetes Cluster ist nicht erreichbar."
        error "Bitte Docker Desktop starten und Kubernetes aktivieren, bevor die Demo gestartet wird."
        error "Erwarteter Kontext: '$EXPECTED_CONTEXT'"
        return 1
    fi
    return 0
}

require_namespace() {
    local namespace="$1"
    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        error "Namespace '$namespace' existiert nicht."
        exit 1
    fi
}

require_service() {
    local namespace="$1"
    local service="$2"
    if ! kubectl get service "$service" -n "$namespace" >/dev/null 2>&1; then
        error "Service '$service' im Namespace '$namespace' wurde nicht gefunden."
        return 1
    fi
}

ensure_argocd() {
    local install_manifest="${ARGOCD_INSTALL_MANIFEST:-https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml}"

    if ! require_cluster_reachable; then
        error "Argo CD konnte nicht installiert werden, weil der Kubernetes-Cluster nicht erreichbar ist."
        error "Manifest: $install_manifest"
        return 1
    fi

    if kubectl get namespace "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
        if kubectl get service "$ARGOCD_SERVICE" -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
            echo "OK: Argo CD ist bereits im Cluster verfügbar."
            return 0
        fi
    fi

    echo "Argo CD wurde nicht gefunden. Starte Installation in Namespace '$ARGOCD_NAMESPACE'..."

    kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml 2>/dev/null | kubectl apply -f - >/dev/null

    if ! kubectl apply -n "$ARGOCD_NAMESPACE" -f "$install_manifest" >/dev/null 2>&1; then
        error "Argo CD konnte nicht installiert werden. Manifest: $install_manifest"
        error "Prüfe Docker Desktop / Kubernetes-Kontext '$EXPECTED_CONTEXT' und den Cluster-Status."
        return 1
    fi

    echo "Warte auf Argo CD Deployment..."
    kubectl rollout status deployment/argocd-server -n "$ARGOCD_NAMESPACE" --timeout=300s >/dev/null 2>&1 || true
    kubectl rollout status deployment/argocd-repo-server -n "$ARGOCD_NAMESPACE" --timeout=300s >/dev/null 2>&1 || true

    if ! kubectl get service "$ARGOCD_SERVICE" -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
        error "Argo CD wurde installiert, aber der Service '$ARGOCD_SERVICE' ist noch nicht verfügbar."
        return 1
    fi

    echo "OK: Argo CD wurde installiert und ist verfügbar."
    return 0
}

is_pid_running() {
    local pid="$1"
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

is_local_port_listening() {
    local port="$1"
    ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"
}

verify_http_endpoint() {
    local name="$1"
    local url="$2"
    local insecure="${3:-false}"
    local http_code

    if [[ "$insecure" == "true" ]]; then
        http_code="$(curl -k -sS -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || true)"
    else
        http_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || true)"
    fi

    if [[ -n "$http_code" && "$http_code" != "000" ]]; then
        echo "OK: $name erreichbar (HTTP $http_code)"
        return 0
    fi

    warning "$name ist unter $url noch nicht erreichbar."
    return 1
}

start_port_forward() {
    local name="$1"
    local namespace="$2"
    local service="$3"
    local ports="$4"
    local local_port="$5"
    local verify_url="$6"
    local insecure="${7:-false}"

    local pid_file="${PID_DIR}/${name}.pid"
    local log_file="${LOG_DIR}/${name}.log"

    echo
    echo "Starte $name ..."

    if ! require_service "$namespace" "$service"; then
        return 1
    fi

    if [[ -f "$pid_file" ]]; then
        local old_pid
        old_pid="$(cat "$pid_file" 2>/dev/null || true)"

        if is_pid_running "$old_pid"; then
            info "$name läuft bereits mit PID $old_pid."
            if verify_http_endpoint "$name" "$verify_url" "$insecure"; then
                return 0
            fi
            warning "PID läuft, Endpoint ist aber nicht erreichbar. PID-Datei wird verworfen."
            rm -f "$pid_file"
        else
            rm -f "$pid_file"
        fi
    fi

    if is_local_port_listening "$local_port"; then
        warning "Lokaler Port $local_port ist bereits belegt."

        if verify_http_endpoint "$name" "$verify_url" "$insecure"; then
            info "$name ist bereits erreichbar. Kein zweiter Port-Forward nötig."
            return 0
        fi

        error "Port $local_port ist belegt, aber $name ist darüber nicht erreichbar."
        echo "Prüfung: ss -lntp | grep ':${local_port}'"
        return 1
    fi

    : >"$log_file"

    nohup kubectl port-forward         -n "$namespace"         "svc/$service"         "$ports"         >"$log_file" 2>&1 &

    local pid=$!
    echo "$pid" >"$pid_file"

    local attempt
    for attempt in {1..10}; do
        if ! is_pid_running "$pid"; then
            break
        fi
        if is_local_port_listening "$local_port"; then
            break
        fi
        sleep 1
    done

    if ! is_pid_running "$pid"; then
        error "$name konnte nicht gestartet werden."
        echo "Letzte Log-Ausgabe:"
        tail -n 20 "$log_file" 2>/dev/null || true
        rm -f "$pid_file"
        return 1
    fi

    if ! is_local_port_listening "$local_port"; then
        error "$name-Prozess läuft, aber Port $local_port lauscht nicht."
        echo "Letzte Log-Ausgabe:"
        tail -n 20 "$log_file" 2>/dev/null || true
        return 1
    fi

    echo "OK: $name Port-Forward gestartet."
    echo "PID: $pid"
    echo "Log: $log_file"

    verify_http_endpoint "$name" "$verify_url" "$insecure" || true
    return 0
}

show_live_status() {
    while true; do
        clear || true

        echo "============================================================"
        echo " PACMAN KUBERNETES LIVE STATUS"
        echo " $(date '+%Y-%m-%d %H:%M:%S')"
        echo "============================================================"
        echo
        echo "Kontext: $(kubectl config current-context 2>/dev/null || echo 'nicht verfügbar')"

        echo
        echo "============================================================"
        echo " DEV PODS"
        echo "============================================================"
        kubectl get pods -n "$DEV_NAMESPACE" -o wide 2>/dev/null || true

        echo
        echo "============================================================"
        echo " PROD PODS"
        echo "============================================================"
        kubectl get pods -n "$PROD_NAMESPACE" -o wide 2>/dev/null || true

        echo
        echo "============================================================"
        echo " PACMAN REPLIKATE"
        echo "============================================================"

        echo
        echo "--- DEV ---"
        kubectl get deployment "$PACMAN_DEPLOYMENT"             -n "$DEV_NAMESPACE"             -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas'             2>/dev/null || true

        echo
        echo "--- PROD ---"
        kubectl get deployment "$PACMAN_DEPLOYMENT"             -n "$PROD_NAMESPACE"             -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas'             2>/dev/null || true

        echo
        echo "============================================================"
        echo " CPU / MEMORY"
        echo "============================================================"

        echo
        echo "--- DEV ---"
        kubectl top pods -n "$DEV_NAMESPACE" 2>/dev/null             | grep -E '^NAME|^pacman-|^mongodb-'             || echo "Keine Resource Metrics verfügbar."

        echo
        echo "--- PROD ---"
        kubectl top pods -n "$PROD_NAMESPACE" 2>/dev/null             | grep -E '^NAME|^pacman-|^mongodb-'             || echo "Keine Resource Metrics verfügbar."

        echo
        echo "============================================================"
        echo " MONGODB STATEFULSETS"
        echo "============================================================"

        echo
        echo "--- DEV ---"
        kubectl get statefulset "$MONGODB_STATEFULSET"             -n "$DEV_NAMESPACE"             -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,CURRENT:.status.currentReplicas'             2>/dev/null || true

        echo
        echo "--- PROD ---"
        kubectl get statefulset "$MONGODB_STATEFULSET"             -n "$PROD_NAMESPACE"             -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,CURRENT:.status.currentReplicas'             2>/dev/null || true

        echo
        echo "============================================================"
        echo " HPA PROD"
        echo "============================================================"
        kubectl get hpa -n "$PROD_NAMESPACE" 2>/dev/null || true

        echo
        echo "============================================================"
        echo " PVC DEV / PROD"
        echo "============================================================"

        echo
        echo "--- DEV ---"
        kubectl get pvc -n "$DEV_NAMESPACE" 2>/dev/null || true

        echo
        echo "--- PROD ---"
        kubectl get pvc -n "$PROD_NAMESPACE" 2>/dev/null || true

        echo
        echo "============================================================"
        echo " ARGO CD APPLICATIONS"
        echo "============================================================"
        kubectl get applications.argoproj.io -n "$ARGOCD_NAMESPACE" 2>/dev/null             || echo "Argo-CD Applications nicht verfügbar."

        echo
        echo "============================================================"
        echo " DEMO-ZUGÄNGE"
        echo "============================================================"
        echo
        echo "Pacman Dev: http://localhost:${PACMAN_DEV_LOCAL_PORT}"
        echo "Pacman Prod: http://localhost:${PACMAN_PROD_LOCAL_PORT}"
        echo "Prometheus: http://localhost:${PROMETHEUS_LOCAL_PORT}"
        echo "Grafana:    http://localhost:${GRAFANA_LOCAL_PORT}"
        echo "Argo CD:    https://localhost:${ARGOCD_LOCAL_PORT}"
        echo
        echo "Aktualisierung alle ${LIVE_INTERVAL}s"
        echo "CTRL+C beendet nur die Live-Anzeige."
        echo "Port-Forwards bleiben aktiv."
        echo "Beenden der Port-Forwards: ./scripts/stop-demo.sh"

        sleep "$LIVE_INTERVAL"
    done
}

handle_interrupt() {
    echo
    echo "============================================================"
    echo " LIVE-STATUS BEENDET"
    echo "============================================================"
    echo
    echo "Die Port-Forwards laufen weiter:"
    echo "Pacman Dev: http://localhost:${PACMAN_DEV_LOCAL_PORT}"
    echo "Pacman Prod: http://localhost:${PACMAN_PROD_LOCAL_PORT}"
    echo "Prometheus: http://localhost:${PROMETHEUS_LOCAL_PORT}"
    echo "Grafana:    http://localhost:${GRAFANA_LOCAL_PORT}"
    echo "Argo CD:    https://localhost:${ARGOCD_LOCAL_PORT}"
    echo
    echo "Zum kontrollierten Beenden:"
    echo "  ./scripts/stop-demo.sh"
    exit 0
}

trap handle_interrupt INT TERM

echo "============================================================"
echo " PACMAN DEMO-UMGEBUNG STARTEN"
echo "============================================================"

echo
echo "[1/7] Voraussetzungen prüfen ..."

require_command kubectl
require_command nohup
require_command curl
require_command ss

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

if [[ -z "$CURRENT_CONTEXT" ]]; then
    error "Kein Kubernetes-Kontext aktiv."
    exit 1
fi

if [[ "$CURRENT_CONTEXT" != "$EXPECTED_CONTEXT" ]]; then
    error "Aktueller Kubernetes-Kontext: '$CURRENT_CONTEXT'"
    error "Erwarteter Kontext: '$EXPECTED_CONTEXT'"
    exit 1
fi

require_cluster_reachable || exit 1

ensure_argocd || exit 1

echo "OK: Kubernetes ist erreichbar."
echo "Kontext: $CURRENT_CONTEXT"

echo
echo "[2/7] Namespaces prüfen ..."

require_namespace "$DEV_NAMESPACE"
require_namespace "$PROD_NAMESPACE"
require_namespace "$MONITORING_NAMESPACE"
require_namespace "$ARGOCD_NAMESPACE"

require_service "$DEV_NAMESPACE" "$PACMAN_SERVICE"
require_service "$PROD_NAMESPACE" "$PACMAN_SERVICE"
require_service "$DEV_NAMESPACE" "$MONGODB_SERVICE"
require_service "$PROD_NAMESPACE" "$MONGODB_SERVICE"
require_service "$MONITORING_NAMESPACE" "$PROMETHEUS_SERVICE"
require_service "$MONITORING_NAMESPACE" "$GRAFANA_SERVICE"
require_service "$ARGOCD_NAMESPACE" "$ARGOCD_SERVICE"

echo "OK: Erforderliche Namespaces und Services vorhanden."

echo
echo "[3/7] Pacman Dev prüfen ..."

kubectl rollout status     "deployment/$PACMAN_DEPLOYMENT"     -n "$DEV_NAMESPACE"     --timeout=180s

DEV_REPLICAS="$(
    kubectl get deployment "$PACMAN_DEPLOYMENT"         -n "$DEV_NAMESPACE"         -o jsonpath='{.spec.replicas}'
)"

echo "Dev Soll-Replikate: $DEV_REPLICAS"

if [[ "$DEV_REPLICAS" != "1" ]]; then
    warning "Dev besitzt aktuell nicht die erwartete eine Replik."
fi

echo
echo "[4/7] Pacman Prod prüfen ..."

kubectl rollout status     "deployment/$PACMAN_DEPLOYMENT"     -n "$PROD_NAMESPACE"     --timeout=180s

PROD_REPLICAS="$(
    kubectl get deployment "$PACMAN_DEPLOYMENT"         -n "$PROD_NAMESPACE"         -o jsonpath='{.spec.replicas}'
)"

echo "Prod Soll-Replikate: $PROD_REPLICAS"

if [[ "$PROD_REPLICAS" != "3" ]]; then
    warning "Prod besitzt aktuell nicht die erwarteten drei Replikate."
fi

echo
echo "[5/7] Kubernetes-Zustand erfassen ..."

echo
echo "============================================================"
echo " PACMAN DEV"
echo "============================================================"
kubectl get pods -n "$DEV_NAMESPACE" -o wide

echo
echo "============================================================"
echo " PACMAN PROD"
echo "============================================================"
kubectl get pods -n "$PROD_NAMESPACE" -o wide

echo
echo "============================================================"
echo " MONGODB STATEFULSETS"
echo "============================================================"

echo
echo "--- DEV ---"
kubectl get statefulset "$MONGODB_STATEFULSET"     -n "$DEV_NAMESPACE"     -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,CURRENT:.status.currentReplicas'     || true

echo
echo "--- PROD ---"
kubectl get statefulset "$MONGODB_STATEFULSET"     -n "$PROD_NAMESPACE"     -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,CURRENT:.status.currentReplicas'     || true

echo
echo "============================================================"
echo " HPA PROD"
echo "============================================================"
kubectl get hpa -n "$PROD_NAMESPACE" || true

echo
echo "============================================================"
echo " PVC DEV"
echo "============================================================"
kubectl get pvc -n "$DEV_NAMESPACE" || true

echo
echo "============================================================"
echo " PVC PROD"
echo "============================================================"
kubectl get pvc -n "$PROD_NAMESPACE" || true

echo
echo "============================================================"
echo " BACKUP CRONJOBS"
echo "============================================================"

echo
echo "--- DEV ---"
kubectl get cronjobs -n "$DEV_NAMESPACE" || true

echo
echo "--- PROD ---"
kubectl get cronjobs -n "$PROD_NAMESPACE" || true

echo
echo "============================================================"
echo " MONITORING STACK"
echo "============================================================"
kubectl get pods -n "$MONITORING_NAMESPACE"

echo
echo "[6/7] Port-Forwards starten ..."

PORT_FORWARD_ERRORS=0

start_port_forward     "prometheus"     "$MONITORING_NAMESPACE"     "$PROMETHEUS_SERVICE"     "$PROMETHEUS_PORT"     "$PROMETHEUS_LOCAL_PORT"     "http://localhost:${PROMETHEUS_LOCAL_PORT}"     "false"     || PORT_FORWARD_ERRORS=$((PORT_FORWARD_ERRORS + 1))

start_port_forward     "grafana"     "$MONITORING_NAMESPACE"     "$GRAFANA_SERVICE"     "$GRAFANA_PORT"     "$GRAFANA_LOCAL_PORT"     "http://localhost:${GRAFANA_LOCAL_PORT}"     "false"     || PORT_FORWARD_ERRORS=$((PORT_FORWARD_ERRORS + 1))

start_port_forward     "argocd"     "$ARGOCD_NAMESPACE"     "$ARGOCD_SERVICE"     "$ARGOCD_PORT"     "$ARGOCD_LOCAL_PORT"     "https://localhost:${ARGOCD_LOCAL_PORT}"     "true"     || PORT_FORWARD_ERRORS=$((PORT_FORWARD_ERRORS + 1))

start_port_forward     "pacman-dev"     "$DEV_NAMESPACE"     "$PACMAN_SERVICE"     "$PACMAN_DEV_PORT"     "$PACMAN_DEV_LOCAL_PORT"     "http://localhost:${PACMAN_DEV_LOCAL_PORT}"     "false"     || PORT_FORWARD_ERRORS=$((PORT_FORWARD_ERRORS + 1))

start_port_forward     "pacman-prod"     "$PROD_NAMESPACE"     "$PACMAN_SERVICE"     "$PACMAN_PROD_PORT"     "$PACMAN_PROD_LOCAL_PORT"     "http://localhost:${PACMAN_PROD_LOCAL_PORT}"     "false"     || PORT_FORWARD_ERRORS=$((PORT_FORWARD_ERRORS + 1))

if (( PORT_FORWARD_ERRORS > 0 )); then
    echo
    error "$PORT_FORWARD_ERRORS Port-Forward(s) konnten nicht erfolgreich bereitgestellt werden."
    echo "Bitte Logs prüfen:"
    echo "  $LOG_DIR"
    echo
    echo "Laufende Listener:"
    ss -lntp 2>/dev/null | grep -E ':3000|:8081|:8082|:8443|:9090' || true
    exit 1
fi

echo
echo "[7/7] Demo-Umgebung bereit."

echo
echo "============================================================"
echo " PACMAN DEMO-UMGEBUNG BEREIT"
echo "============================================================"
echo
echo "Dev:"
echo "  Erwartet: 1 Pacman-Replik"
echo "  Gefunden: $DEV_REPLICAS"
echo
echo "Prod:"
echo "  Erwartet: 3 Pacman-Replikate"
echo "  Gefunden: $PROD_REPLICAS"
echo
echo "Pacman Dev: http://localhost:${PACMAN_DEV_LOCAL_PORT}"
echo "Pacman Prod: http://localhost:${PACMAN_PROD_LOCAL_PORT}"
echo "Prometheus: http://localhost:${PROMETHEUS_LOCAL_PORT}"
echo "Grafana:    http://localhost:${GRAFANA_LOCAL_PORT}"
echo "Argo CD:    https://localhost:${ARGOCD_LOCAL_PORT}"
echo
echo "Port-Forward Logs:"
echo "  $LOG_DIR"
echo
echo "PID-Dateien:"
echo "  $PID_DIR"
echo
echo "Live-Status startet jetzt."
echo "CTRL+C beendet nur die Live-Anzeige."
echo "Port-Forwards bleiben aktiv."
echo

sleep 3
show_live_status
