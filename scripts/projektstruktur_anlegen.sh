#!/bin/bash

set -e

echo "========================================="
echo " DevOps Pacman Projektstruktur anlegen"
echo "========================================="

PROJECT="devops-pacman-abschlussprojekt"

set -e

# Projektwurzel = eine Ebene über dem Skript
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Projektverzeichnis:"
echo "$PROJECT"

#############################
# Ausgangsmaterial
#############################

mkdir -p "$PROJECT/ausgangsmaterial"

touch "$PROJECT/ausgangsmaterial/pacman-master.zip"
touch "$PROJECT/ausgangsmaterial/docker.zip"

#############################
# pacman-app
#############################

mkdir -p "$PROJECT/pacman-app"/{bin,lib,public,routes,views}
mkdir -p "$PROJECT/pacman-app/tests"
mkdir -p "$PROJECT/pacman-app/scripts"
mkdir -p "$PROJECT/pacman-app/.github/workflows"

touch "$PROJECT/pacman-app/app.js"
touch "$PROJECT/pacman-app/package.json"
touch "$PROJECT/pacman-app/package-lock.json"
touch "$PROJECT/pacman-app/Dockerfile"
touch "$PROJECT/pacman-app/.dockerignore"
touch "$PROJECT/pacman-app/compose.yaml"
touch "$PROJECT/pacman-app/.env.example"

touch "$PROJECT/pacman-app/tests/smoke-test.sh"

touch "$PROJECT/pacman-app/scripts/local-start.sh"
touch "$PROJECT/pacman-app/scripts/local-stop.sh"
touch "$PROJECT/pacman-app/scripts/load-test.sh"

touch "$PROJECT/pacman-app/.github/workflows/ci.yml"
touch "$PROJECT/pacman-app/.github/workflows/release.yml"

touch "$PROJECT/pacman-app/README.md"

#############################
# pacman-gitops
#############################

mkdir -p "$PROJECT/pacman-gitops/apps/pacman/base"
mkdir -p "$PROJECT/pacman-gitops/apps/pacman/overlays/dev"
mkdir -p "$PROJECT/pacman-gitops/apps/pacman/overlays/prod"

mkdir -p "$PROJECT/pacman-gitops/clusters/docker-desktop/argocd"

mkdir -p "$PROJECT/pacman-gitops/platform/ingress-nginx"
mkdir -p "$PROJECT/pacman-gitops/platform/metrics-server"
mkdir -p "$PROJECT/pacman-gitops/platform/monitoring"

touch "$PROJECT/pacman-gitops/README.md"

#############################
# Planung
#############################

mkdir -p "$PROJECT/planung"

touch "$PROJECT/planung/arbeitspakete_und_zeitplanung.csv"
touch "$PROJECT/planung/projektstruktur.drawio"
touch "$PROJECT/planung/commit-strategie.xlsx"

#############################
# Dokumentation
#############################

mkdir -p "$PROJECT/dokumentation"

touch "$PROJECT/dokumentation/00_projektuebersicht.docx"
touch "$PROJECT/dokumentation/01_codeanalyse_und_anforderungen.docx"
touch "$PROJECT/dokumentation/02_architektur_und_repositories.docx"
touch "$PROJECT/dokumentation/03_containerisierung_und_compose.docx"
touch "$PROJECT/dokumentation/04_github_actions_und_registry.docx"
touch "$PROJECT/dokumentation/05_kubernetes_architektur.docx"
touch "$PROJECT/dokumentation/06_kubernetes_sicherheit_und_betrieb.docx"
touch "$PROJECT/dokumentation/07_argocd_gitops_und_promotion.docx"
touch "$PROJECT/dokumentation/08_monitoring_backup_restore.docx"
touch "$PROJECT/dokumentation/09_tests_fehler_und_devopsfaelle.docx"
touch "$PROJECT/dokumentation/10_uebergabe_und_betriebsanleitung.docx"
touch "$PROJECT/dokumentation/abschlussdokumentation.docx"

#############################
# Screenshots
#############################

mkdir -p "$PROJECT/screenshots"/{github,github-actions,docker,ghcr,kubernetes,argocd,prometheus,grafana,tests}

#############################
# Weitere Ordner
#############################

mkdir -p "$PROJECT/daten"
mkdir -p "$PROJECT/textdateien"

mkdir -p "$PROJECT/praesentation/bilder"

touch "$PROJECT/praesentation/IHK_Praesentation.pptx"

#############################
# Skripte ausführbar machen
#############################

chmod +x "$PROJECT/pacman-app/tests/smoke-test.sh"

chmod +x "$PROJECT/pacman-app/scripts/local-start.sh"
chmod +x "$PROJECT/pacman-app/scripts/local-stop.sh"
chmod +x "$PROJECT/pacman-app/scripts/load-test.sh"

#############################
# Ausgabe
#############################

echo ""
echo "Projektstruktur erfolgreich erstellt."
echo ""

tree "$PROJECT"