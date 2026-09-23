#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="pacman-dev"
DEPLOYMENT="pacman"
ORIGINAL_REPLICAS=1
TEST_REPLICAS=2

echo "=================================================="
echo " Pacman Live-Demo: Skalierung + GitOps Self-Heal"
echo "=================================================="
echo

# -------------------------------------------------
# 1. Ressource prüfen
# -------------------------------------------------

echo "[1] Prüfe Deployment ..."

kubectl get deployment "$DEPLOYMENT" \
  -n "$NAMESPACE"

echo

CURRENT=$(kubectl get deployment "$DEPLOYMENT" \
  -n "$NAMESPACE" \
  -o jsonpath='{.spec.replicas}')

echo "Aktueller Sollwert im Cluster: $CURRENT"
echo "GitOps-Sollzustand erwartet:   $ORIGINAL_REPLICAS"
echo

# -------------------------------------------------
# 2. Bestätigung
# -------------------------------------------------

read -r -p "Skalierung von 1 auf 2 auslösen? [y/N]: " ANSWER

if [[ ! "$ANSWER" =~ ^[Yy]$ ]]; then
    echo "Demo abgebrochen."
    exit 0
fi

# -------------------------------------------------
# 3. Manuelle Skalierung
# -------------------------------------------------

echo
echo "[2] Skaliere Pacman kontrolliert auf $TEST_REPLICAS Replikate ..."

kubectl scale deployment "$DEPLOYMENT" \
  -n "$NAMESPACE" \
  --replicas="$TEST_REPLICAS"

echo
echo "Manuelle Änderung wurde erzeugt."
echo "Damit weicht der Cluster vom GitOps-Sollzustand ab."
echo

# -------------------------------------------------
# 4. Zustand beobachten
# -------------------------------------------------

echo "[3] Beobachte Deployment und Pods ..."
echo

for i in {1..20}; do

    DESIRED=$(kubectl get deployment "$DEPLOYMENT" \
      -n "$NAMESPACE" \
      -o jsonpath='{.spec.replicas}')

    READY=$(kubectl get deployment "$DEPLOYMENT" \
      -n "$NAMESPACE" \
      -o jsonpath='{.status.readyReplicas}')

    AVAILABLE=$(kubectl get deployment "$DEPLOYMENT" \
      -n "$NAMESPACE" \
      -o jsonpath='{.status.availableReplicas}')

    READY=${READY:-0}
    AVAILABLE=${AVAILABLE:-0}

    echo "Soll=$DESIRED | Ready=$READY | Verfügbar=$AVAILABLE"

    kubectl get pods \
      -n "$NAMESPACE" \
      -l app.kubernetes.io/name=pacman \
      --no-headers 2>/dev/null || true

    echo "--------------------------------------------------"

    sleep 3
done

# -------------------------------------------------
# 5. Endzustand
# -------------------------------------------------

echo
echo "[4] Endzustand:"
echo

kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE" \
  -l app.kubernetes.io/name=pacman

echo
echo "Erwartung bei aktiviertem Argo-CD Self Heal:"
echo
echo "  Manuelle Skalierung: 1 -> 2"
echo "  Drift wird erkannt"
echo "  Argo CD setzt zurück auf Git-Sollzustand: 1"
echo
echo "Demo beendet."