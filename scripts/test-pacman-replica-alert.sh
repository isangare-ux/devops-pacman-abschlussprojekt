#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="pacman-dev"
PACMAN_DEPLOYMENT="pacman"
MONGODB_STATEFULSET="mongodb"

echo "=================================================="
echo " Pacman Alert-Test: nicht verfügbare Replikate"
echo "=================================================="
echo

# -------------------------------------------------
# 1. Voraussetzungen prüfen
# -------------------------------------------------

echo "[1] Prüfe Kubernetes-Ressourcen ..."

kubectl get deployment "$PACMAN_DEPLOYMENT" \
  -n "$NAMESPACE" >/dev/null

kubectl get statefulset "$MONGODB_STATEFULSET" \
  -n "$NAMESPACE" >/dev/null

echo "OK"
echo

# -------------------------------------------------
# 2. Ausgangszustand
# -------------------------------------------------

echo "[2] Ausgangszustand:"
echo

kubectl get deployment "$PACMAN_DEPLOYMENT" -n "$NAMESPACE"
kubectl get statefulset "$MONGODB_STATEFULSET" -n "$NAMESPACE"

echo
echo "Pods:"
kubectl get pods -n "$NAMESPACE"

echo
echo "Erwartung vor dem Test:"
echo "  Pacman Soll:       1"
echo "  Pacman Verfügbar:  1"
echo "  Differenz:         0"
echo

# -------------------------------------------------
# 3. Bestätigung
# -------------------------------------------------

read -r -p "MongoDB-Ausfall jetzt auslösen? [y/N]: " ANSWER

if [[ ! "$ANSWER" =~ ^[Yy]$ ]]; then
    echo
    echo "Test abgebrochen."
    echo "Es wurde nichts verändert."
    exit 0
fi

# -------------------------------------------------
# 4. Fehler auslösen
# -------------------------------------------------

echo
echo "[3] MongoDB wird kontrolliert auf 0 skaliert ..."

kubectl scale statefulset "$MONGODB_STATEFULSET" \
  -n "$NAMESPACE" \
  --replicas=0

echo
echo "MongoDB-Ausfall wurde ausgelöst."

# -------------------------------------------------
# 5. Auf Pacman NotReady warten
# -------------------------------------------------

echo
echo "[4] Warte darauf, dass Pacman nicht mehr verfügbar ist ..."
echo

for i in {1..24}; do

    DESIRED=$(kubectl get deployment "$PACMAN_DEPLOYMENT" \
      -n "$NAMESPACE" \
      -o jsonpath='{.spec.replicas}')

    AVAILABLE=$(kubectl get deployment "$PACMAN_DEPLOYMENT" \
      -n "$NAMESPACE" \
      -o jsonpath='{.status.availableReplicas}')

    AVAILABLE=${AVAILABLE:-0}

    DIFFERENCE=$((DESIRED - AVAILABLE))

    echo "Soll=$DESIRED | Verfügbar=$AVAILABLE | Differenz=$DIFFERENCE"

    if [[ "$DIFFERENCE" -gt 0 ]]; then
        echo
        echo "=================================================="
        echo " ALERT-ZUSTAND ERREICHT"
        echo "=================================================="
        echo
        echo "Soll:        $DESIRED"
        echo "Verfügbar:   $AVAILABLE"
        echo "Differenz:   $DIFFERENCE"
        echo
        break
    fi

    sleep 5

done

# -------------------------------------------------
# 6. Grafana beobachten
# -------------------------------------------------

echo
echo ">>> Jetzt Grafana beobachten."
echo
echo "Deine PromQL-Query sollte anzeigen:"
echo
echo "  Soll        = 1"
echo "  Verfügbar   = 0"
echo "  Differenz   = 1"
echo
echo "Je nach Grafana-Konfiguration:"
echo
echo "  Normal -> Pending -> Firing"
echo
echo "MongoDB bleibt AUS."
echo
echo "Erst nach dem Grafana-Screenshot ENTER drücken!"
echo

read -r -p "ENTER drücken, um MongoDB wiederherzustellen ..."

# -------------------------------------------------
# 7. Wiederherstellung
# -------------------------------------------------

echo
echo "[5] MongoDB wird wieder auf 1 skaliert ..."

kubectl scale statefulset "$MONGODB_STATEFULSET" \
  -n "$NAMESPACE" \
  --replicas=1

echo
echo "Warte auf MongoDB ..."

kubectl rollout status \
  statefulset/"$MONGODB_STATEFULSET" \
  -n "$NAMESPACE" \
  --timeout=120s || true

# -------------------------------------------------
# 8. Auf Pacman-Wiederherstellung warten
# -------------------------------------------------

echo
echo "[6] Warte auf Pacman-Wiederherstellung ..."

for i in {1..24}; do

    DESIRED=$(kubectl get deployment "$PACMAN_DEPLOYMENT" \
      -n "$NAMESPACE" \
      -o jsonpath='{.spec.replicas}')

    AVAILABLE=$(kubectl get deployment "$PACMAN_DEPLOYMENT" \
      -n "$NAMESPACE" \
      -o jsonpath='{.status.availableReplicas}')

    AVAILABLE=${AVAILABLE:-0}

    DIFFERENCE=$((DESIRED - AVAILABLE))

    echo "Soll=$DESIRED | Verfügbar=$AVAILABLE | Differenz=$DIFFERENCE"

    if [[ "$DIFFERENCE" -eq 0 ]]; then
        echo
        echo "=================================================="
        echo " NORMALZUSTAND WIEDERHERGESTELLT"
        echo "=================================================="
        break
    fi

    sleep 5

done

echo
echo "Finaler Kubernetes-Zustand:"
echo

kubectl get deployment "$PACMAN_DEPLOYMENT" -n "$NAMESPACE"
kubectl get statefulset "$MONGODB_STATEFULSET" -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE"

echo
echo "Erwarteter Grafana-Endzustand:"
echo
echo "  Soll        = 1"
echo "  Verfügbar   = 1"
echo "  Differenz   = 0"
echo "  Alert       = Normal / Resolved"
echo
echo "Test beendet."