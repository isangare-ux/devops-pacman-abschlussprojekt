#!/usr/bin/env bash

set -u

# ============================================================
# Pacman Demo-Port-Forwards kontrolliert beenden
#
# Beendet:
# - Prometheus
# - Grafana
# - Argo CD
# - Pacman Dev
# - Pacman Prod
#
# Hinweis:
# MongoDB wird bewusst NICHT per Port-Forward veröffentlicht.
# Deshalb gibt es für MongoDB keinen eigenen Port-Forward-Prozess,
# der hier beendet werden müsste.
# ============================================================

PID_DIR="${HOME}/pacman-portforward-pids"

echo "============================================================"
echo " PACMAN DEMO-PORT-FORWARDS BEENDEN"
echo "============================================================"

stop_port_forward() {
    local name="$1"
    local pid_file="${PID_DIR}/${name}.pid"

    echo
    echo "Prüfe $name ..."

    if [[ ! -f "$pid_file" ]]; then
        echo "INFO: Keine PID-Datei für $name vorhanden."
        return 0
    fi

    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"

    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true

        # Kurz auf sauberes Prozessende warten.
        for _ in {1..10}; do
            if ! kill -0 "$pid" 2>/dev/null; then
                break
            fi
            sleep 0.2
        done

        if kill -0 "$pid" 2>/dev/null; then
            echo "WARNUNG: $name Prozess PID $pid läuft noch."
        else
            echo "OK: $name beendet (PID $pid)."
        fi
    else
        echo "INFO: $name läuft nicht mehr."
    fi

    rm -f "$pid_file"
}

stop_port_forward "prometheus"
stop_port_forward "grafana"
stop_port_forward "argocd"
stop_port_forward "pacman-dev"
stop_port_forward "pacman-prod"

echo
echo "============================================================"
echo " PORT-FORWARDS BEENDET"
echo "============================================================"
echo
echo "MongoDB Dev/Prod bleiben im Kubernetes-Cluster aktiv."
echo "Es wurde kein MongoDB-Port nach außen veröffentlicht."
