#!/bin/bash
#
# Legt die vollständige Projektstruktur für das IHK-Abschlussprojekt
# "DevOps Pacman" gemäß Aufgabenstellung (Arbeitspakete 1-33) an.
# Bereits vorhandene Dateien/Ordner werden NICHT überschrieben, nur
# fehlende werden ergänzt.

set -e

echo "========================================="
echo " DevOps Pacman Projektstruktur anlegen"
echo "========================================="

# Projektwurzel = eine Ebene über dem Skript
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Projektverzeichnis:"
echo "$PROJECT"
echo ""

#############################
# Hilfsfunktionen
#############################

create_dir() {
    local d="$PROJECT/$1"
    if [[ -d "$d" ]]; then
        echo "  vorhanden : $1/"
    else
        mkdir -p "$d"
        echo "  erstellt  : $1/"
    fi
}

create_file() {
    local f="$PROJECT/$1"
    if [[ -f "$f" ]]; then
        echo "  vorhanden : $1"
    else
        mkdir -p "$(dirname "$f")"
        touch "$f"
        echo "  erstellt  : $1"
    fi
}

create_exec_file() {
    create_file "$1"
    chmod +x "$PROJECT/$1"
}

#############################
# Ausgangsmaterial (AP: Codeanalyse)
#############################

echo "--- ausgangsmaterial/ ---"
create_dir "ausgangsmaterial"

PACMAN_ZIP="$PROJECT/ausgangsmaterial/pacman-master.zip"
DOCKER_ZIP="$PROJECT/ausgangsmaterial/docker.zip"

if [[ ! -f "$PACMAN_ZIP" ]]; then
    echo "❌ Datei fehlt: pacman-master.zip"
    echo "Bitte Originaldatei nach: $PROJECT/ausgangsmaterial/"
    exit 1
fi

if [[ ! -f "$DOCKER_ZIP" ]]; then
    echo "❌ Datei fehlt: docker.zip"
    echo "Bitte Originaldatei nach: $PROJECT/ausgangsmaterial/"
    exit 1
fi

if [[ ! -f "$PROJECT/ausgangsmaterial/pacman-master.sha256" ]]; then
    sha256sum "$PACMAN_ZIP" > "$PROJECT/ausgangsmaterial/pacman-master.sha256"
    echo "  erstellt  : ausgangsmaterial/pacman-master.sha256"
else
    echo "  vorhanden : ausgangsmaterial/pacman-master.sha256"
fi

if [[ ! -f "$PROJECT/ausgangsmaterial/docker.sha256" ]]; then
    sha256sum "$DOCKER_ZIP" > "$PROJECT/ausgangsmaterial/docker.sha256"
    echo "  erstellt  : ausgangsmaterial/docker.sha256"
else
    echo "  vorhanden : ausgangsmaterial/docker.sha256"
fi

#############################
# pacman-app
#############################

echo "--- pacman-app/ ---"
create_dir "pacman-app/bin"
create_dir "pacman-app/lib"
create_dir "pacman-app/public"
create_dir "pacman-app/routes"
create_dir "pacman-app/views"
create_dir "pacman-app/tests"
create_dir "pacman-app/scripts"
create_dir "pacman-app/.github/workflows"

create_file "pacman-app/app.js"
create_file "pacman-app/package.json"
create_file "pacman-app/package-lock.json"
create_file "pacman-app/Dockerfile"
create_file "pacman-app/.dockerignore"
create_file "pacman-app/compose.yaml"
create_file "pacman-app/.env.example"
create_file "pacman-app/README.md"

create_exec_file "pacman-app/tests/smoke-test.sh"
create_exec_file "pacman-app/scripts/local-start.sh"
create_exec_file "pacman-app/scripts/local-stop.sh"
create_exec_file "pacman-app/scripts/load-test.sh"

create_file "pacman-app/.github/workflows/ci.yml"
create_file "pacman-app/.github/workflows/release.yml"

#############################
# pacman-gitops
#############################

echo "--- pacman-gitops/ ---"
create_dir "pacman-gitops/apps/pacman/base"
create_dir "pacman-gitops/apps/pacman/overlays/dev"
create_dir "pacman-gitops/apps/pacman/overlays/prod"
create_dir "pacman-gitops/clusters/docker-desktop/argocd"
create_dir "pacman-gitops/platform/ingress-nginx"
create_dir "pacman-gitops/platform/metrics-server"
create_dir "pacman-gitops/platform/monitoring"
create_dir "pacman-gitops/scripts"

create_file "pacman-gitops/README.md"

# Kustomize Base und Overlays (AP15)
create_file "pacman-gitops/apps/pacman/base/kustomization.yaml"
create_file "pacman-gitops/apps/pacman/overlays/dev/kustomization.yaml"
create_file "pacman-gitops/apps/pacman/overlays/prod/kustomization.yaml"

# Deployment, Service, ServiceAccount (AP16)
create_file "pacman-gitops/apps/pacman/base/deployment.yaml"
create_file "pacman-gitops/apps/pacman/base/service.yaml"
create_file "pacman-gitops/apps/pacman/base/serviceaccount.yaml"

# MongoDB StatefulSet, Service, Init-ConfigMap (AP17)
create_file "pacman-gitops/apps/pacman/base/mongodb-statefulset.yaml"
create_file "pacman-gitops/apps/pacman/base/mongodb-service.yaml"
create_file "pacman-gitops/apps/pacman/base/mongodb-init-configmap.yaml"

# ConfigMap, Secret (AP18)
create_file "pacman-gitops/apps/pacman/base/configmap.yaml"
create_file "pacman-gitops/apps/pacman/base/secret.example.yaml"
create_exec_file "pacman-gitops/scripts/create-local-secrets.sh"

# Ingress, NetworkPolicy (AP20)
create_file "pacman-gitops/apps/pacman/base/ingress.yaml"
create_file "pacman-gitops/apps/pacman/base/networkpolicy.yaml"
create_file "pacman-gitops/platform/ingress-nginx/values.yaml"

# HPA, PDB, LimitRange, ResourceQuota (AP21)
create_file "pacman-gitops/apps/pacman/base/hpa.yaml"
create_file "pacman-gitops/apps/pacman/base/pdb.yaml"
create_file "pacman-gitops/apps/pacman/base/limitrange.yaml"
create_file "pacman-gitops/apps/pacman/base/resourcequota.yaml"
create_file "pacman-gitops/platform/metrics-server/values.yaml"

# Argo CD AppProject und Applications (AP22)
create_file "pacman-gitops/clusters/docker-desktop/argocd/project.yaml"
create_file "pacman-gitops/clusters/docker-desktop/argocd/application-dev.yaml"
create_file "pacman-gitops/clusters/docker-desktop/argocd/application-prod.yaml"

# Monitoring (AP24)
create_file "pacman-gitops/platform/monitoring/values.yaml"

# Backup / Restore (AP25)
create_file "pacman-gitops/apps/pacman/base/backup-pvc.yaml"
create_file "pacman-gitops/apps/pacman/base/backup-cronjob.yaml"
create_file "pacman-gitops/apps/pacman/base/restore-job-template.yaml"

# Betriebsautomatisierung (AP26)
create_exec_file "pacman-gitops/scripts/cluster-status.sh"
create_exec_file "pacman-gitops/scripts/preflight-check.sh"
create_exec_file "pacman-gitops/scripts/collect-diagnostics.sh"

#############################
# Planung
#############################

echo "--- planung/ ---"
create_dir "planung"
create_file "planung/arbeitspakete_und_zeitplanung.csv"
create_file "planung/projektstruktur.drawio"
create_file "planung/commit-strategie.xlsx"

#############################
# Dokumentation
#############################

echo "--- dokumentation/ ---"
create_dir "dokumentation"
create_file "dokumentation/00_projektuebersicht.docx"
create_file "dokumentation/01_codeanalyse_und_anforderungen.docx"
create_file "dokumentation/02_architektur_und_repositories.docx"
create_file "dokumentation/03_containerisierung_und_compose.docx"
create_file "dokumentation/04_github_actions_und_registry.docx"
create_file "dokumentation/05_kubernetes_architektur.docx"
create_file "dokumentation/06_kubernetes_sicherheit_und_betrieb.docx"
create_file "dokumentation/07_argocd_gitops_und_promotion.docx"
create_file "dokumentation/08_monitoring_backup_restore.docx"
create_file "dokumentation/09_tests_fehler_und_devopsfaelle.docx"
create_file "dokumentation/10_uebergabe_und_betriebsanleitung.docx"
create_file "dokumentation/abschlussdokumentation.docx"

#############################
# Daten (CSV-Nachweise je Arbeitspaket)
#############################

echo "--- daten/ ---"
create_dir "daten"
create_file "daten/codeanalyse.csv"                        # AP08
create_file "daten/werkzeugmatrix.csv"                     # AP09
create_file "daten/repository_und_branch_plan.csv"         # AP10
create_file "daten/image_und_build_plan.csv"               # AP11
create_file "daten/compose_serviceplan.csv"                # AP12
create_file "daten/pipeline_matrix.csv"                     # AP13
create_file "daten/release_history.csv"                     # AP14
create_file "daten/kubernetes_ressourcenplan.csv"           # AP15
create_file "daten/umgebungsmatrix.csv"                     # AP15
create_file "daten/deployment_und_service_plan.csv"         # AP16
create_file "daten/persistenz_und_datenbankplan.csv"        # AP17
create_file "daten/configmap_und_secret_plan.csv"           # AP18
create_file "daten/probe_und_ressourcenplan.csv"            # AP19
create_file "daten/netzwerk_und_ingress_plan.csv"           # AP20
create_file "daten/networkpolicy_matrix.csv"                # AP20
create_file "daten/skalierung_und_namespace_grenzen.csv"    # AP21
create_file "daten/gitops_promotionen.csv"                  # AP23
create_file "daten/monitoring_und_alert_plan.csv"           # AP24
create_file "daten/backup_restore_plan.csv"                 # AP25
create_file "daten/devopsfaelle.csv"                        # AP28
create_file "daten/testprotokoll.csv"                       # AP29
create_file "daten/fehlerprotokoll.csv"                     # AP30

#############################
# Textdateien (Nachweise)
#############################

echo "--- textdateien/ ---"
create_dir "textdateien"
create_file "textdateien/ausgangsmaterial_pruefsummen.txt"     # AP08
create_file "textdateien/installations_und_versionsnachweis.txt" # AP09
create_file "textdateien/git_nachweis.txt"                     # AP10
create_file "textdateien/docker_build_nachweis.txt"            # AP11
create_file "textdateien/ci_workflow_nachweis.txt"             # AP13
create_file "textdateien/ghcr_und_release_nachweis.txt"        # AP14
create_file "textdateien/securitycontext_nachweis.txt"         # AP19
create_file "textdateien/argocd_sync_nachweis.txt"             # AP22
create_file "textdateien/promotion_und_rollback_nachweis.txt"  # AP23
create_file "textdateien/monitoring_nachweis.txt"              # AP24
create_file "textdateien/backup_restore_nachweis.txt"          # AP25
create_file "textdateien/betriebsbefehle.txt"                  # AP26
create_file "textdateien/offene_punkte.txt"                    # AP28 / AP33

#############################
# Screenshots (ein Ordner je Arbeitspaket mit Nachweis)
#############################

echo "--- screenshots/ ---"
create_dir "screenshots/01_codeanalyse"            # AP08
create_dir "screenshots/02_arbeitsumgebung"        # AP09
create_dir "screenshots/03_git_github"             # AP10
create_dir "screenshots/04_docker_image"           # AP11
create_dir "screenshots/05_compose"                # AP12
create_dir "screenshots/06_github_actions_ci"      # AP13
create_dir "screenshots/07_ghcr_release"           # AP14
create_dir "screenshots/08_kubernetes_architektur" # AP15
create_dir "screenshots/09_deployment_service"     # AP16
create_dir "screenshots/10_mongodb_persistenz"     # AP17
create_dir "screenshots/11_config_secret"          # AP18
create_dir "screenshots/12_probes_security"        # AP19
create_dir "screenshots/13_ingress_networkpolicy"  # AP20
create_dir "screenshots/14_hpa_quota"              # AP21
create_dir "screenshots/15_argocd"                 # AP22
create_dir "screenshots/16_promotion_rollback"     # AP23
create_dir "screenshots/17_monitoring"             # AP24
create_dir "screenshots/18_backup_restore"         # AP25
create_dir "screenshots/19_betriebsskripte"        # AP26
create_dir "screenshots/20_devopsfaelle"           # AP28
create_dir "screenshots/21_tests"                  # AP29
create_dir "screenshots/22_fehleranalyse"          # AP30
create_dir "screenshots/23_uebergabe"              # AP33

#############################
# Präsentation
#############################

echo "--- praesentation/ ---"
create_dir "praesentation/bilder"
create_file "praesentation/IHK_Praesentation.pptx"

#############################
# Ausgabe
#############################

echo ""
echo "Projektstruktur erfolgreich geprüft/ergänzt."
echo ""

command -v tree >/dev/null 2>&1 && tree "$PROJECT" -I '.git|.venv|node_modules'
