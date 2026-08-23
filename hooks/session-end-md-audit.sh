#!/bin/bash
#
# session-end-md-audit.sh
# Audit automatique des .md du projet lors de la fin de session.
#
# Detecte les .md devenus obsoletes a cause des changements de la session :
#   1. Liens markdown cassés (vers fichiers/dossiers supprimés)
#   2. Dates "Dernière mise à jour" potentiellement trop anciennes
#   3. Mentions de fichiers/dossiers qui n'existent plus
#   4. Statuts contradictoires ("à créer" alors que le fichier existe)
#
# Usage :
#   ./session-end-md-audit.sh [PROJECT_DIR]
#
# Sortie :
#   - Liste des fichiers .md a verifier ou corriger
#   - Code retour 0 si rien a signaler, 1 sinon
#

set -u

PROJECT_DIR="${1:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
ISSUES_FOUND=0
TOTAL_MD=0

# Couleurs (si terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    GREEN='\033[0;32m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''; YELLOW=''; GREEN=''; CYAN=''; BOLD=''; NC=''
fi

echo -e "${BOLD}${CYAN}=== AUDIT .md FIN DE SESSION ===${NC}"
echo "Projet : $PROJECT_DIR"
echo ""

# Verifier qu'on est dans un git repo
if ! git -C "$PROJECT_DIR" rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${YELLOW}Pas un repo git, audit limite.${NC}"
fi

# Lister tous les .md du projet (en excluant archives, node_modules, .venv, build)
MD_FILES=$(find "$PROJECT_DIR" -name "*.md" \
    -not -path "*/node_modules/*" \
    -not -path "*/.venv/*" \
    -not -path "*/archives/*" \
    -not -path "*/.git/*" \
    -not -path "*/.pytest_cache/*" \
    -not -path "*/build/*" \
    -not -path "*/dist/*" \
    2>/dev/null)

TOTAL_MD=$(echo "$MD_FILES" | wc -l | tr -d ' ')
echo -e "${CYAN}Scan de $TOTAL_MD fichiers .md...${NC}"
echo ""

# === CHECK 1 : Liens markdown casses ===
echo -e "${BOLD}[1/4] Liens markdown casses${NC}"
BROKEN_LINKS=0
while IFS= read -r md_file; do
    [[ -z "$md_file" ]] && continue
    # Extraire les liens markdown relatifs (pas http/https/mailto)
    # Format : [texte](chemin) ou [texte](chemin#ancre)
    grep -nE '\[[^]]+\]\(([^)]+)\)' "$md_file" 2>/dev/null | \
    while IFS=: read -r line_num line_content; do
        # Extraire chaque lien sur la ligne
        echo "$line_content" | grep -oE '\]\(([^)]+)\)' | \
        sed -E 's/\]\(([^)]+)\)/\1/' | \
        while IFS= read -r link; do
            # Ignorer liens externes, ancres pures, mailto
            [[ "$link" =~ ^https?:// ]] && continue
            [[ "$link" =~ ^mailto: ]] && continue
            [[ "$link" =~ ^# ]] && continue
            # Retirer l'ancre #xxx
            target="${link%%#*}"
            [[ -z "$target" ]] && continue
            # Resolve relative path
            md_dir=$(dirname "$md_file")
            full_path="$md_dir/$target"
            # Verifier existence (fichier OU dossier)
            if [[ ! -e "$full_path" ]]; then
                rel_md="${md_file#$PROJECT_DIR/}"
                echo -e "  ${RED}✗${NC} $rel_md:$line_num → lien casse : $target"
                BROKEN_LINKS=$((BROKEN_LINKS + 1))
            fi
        done
    done
done <<< "$MD_FILES"
if [[ "$BROKEN_LINKS" -eq 0 ]]; then
    echo -e "  ${GREEN}✓ aucun lien casse detecte${NC}"
fi
echo ""

# === CHECK 2 : Mentions de fichiers/dossiers connus comme supprimes ===
echo -e "${BOLD}[2/4] References a des fichiers/dossiers supprimes${NC}"
DELETED_REFS=0
# Detecter les fichiers/dossiers supprimes dans les 50 derniers commits
if git -C "$PROJECT_DIR" rev-parse --git-dir > /dev/null 2>&1; then
    DELETED_PATHS=$(git -C "$PROJECT_DIR" log -50 --diff-filter=D --name-only --pretty=format: 2>/dev/null | \
        grep -v '^$' | sort -u)
    if [[ -n "$DELETED_PATHS" ]]; then
        while IFS= read -r deleted; do
            [[ -z "$deleted" ]] && continue
            # Verifier si le chemin n'existe vraiment plus
            [[ -e "$PROJECT_DIR/$deleted" ]] && continue
            # Chercher dans les .md (sauf CHANGELOG, archives, sections historiques)
            HITS=$(echo "$MD_FILES" | xargs grep -lF "$deleted" 2>/dev/null | \
                grep -v "CHANGELOG" | grep -v "archives" || true)
            if [[ -n "$HITS" ]]; then
                while IFS= read -r hit; do
                    [[ -z "$hit" ]] && continue
                    rel_hit="${hit#$PROJECT_DIR/}"
                    line=$(grep -nF "$deleted" "$hit" | head -1 | cut -d: -f1)
                    echo -e "  ${RED}✗${NC} $rel_hit:$line → mention de '$deleted' (supprime)"
                    DELETED_REFS=$((DELETED_REFS + 1))
                done <<< "$HITS"
            fi
        done <<< "$DELETED_PATHS"
    fi
fi
if [[ "$DELETED_REFS" -eq 0 ]]; then
    echo -e "  ${GREEN}✓ aucune reference a un fichier supprime${NC}"
fi
echo ""

# === CHECK 3 : Dates "Dernière mise à jour" potentiellement obsoletes ===
echo -e "${BOLD}[3/4] Dates de mise a jour potentiellement obsoletes${NC}"
STALE_DATES=0
TODAY=$(date +%Y-%m-%d)
# Calculer la date d'il y a 14 jours (compatible macOS)
if date -v-14d +%Y-%m-%d > /dev/null 2>&1; then
    CUTOFF=$(date -v-14d +%Y-%m-%d)
else
    CUTOFF=$(date -d "14 days ago" +%Y-%m-%d 2>/dev/null || echo "2000-01-01")
fi
while IFS= read -r md_file; do
    [[ -z "$md_file" ]] && continue
    # Chercher "Dernière mise à jour : YYYY-MM-DD"
    date_in_file=$(grep -iE "(Derniere|Dernière) mise à jour" "$md_file" 2>/dev/null | \
        grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
    [[ -z "$date_in_file" ]] && continue
    # Comparer
    if [[ "$date_in_file" < "$CUTOFF" ]]; then
        rel_md="${md_file#$PROJECT_DIR/}"
        # Verifier si le fichier a ete modifie dans les 14 derniers jours via git
        last_commit=$(git -C "$PROJECT_DIR" log -1 --format=%cI -- "$md_file" 2>/dev/null | cut -d'T' -f1)
        if [[ -n "$last_commit" && "$last_commit" > "$CUTOFF" ]]; then
            echo -e "  ${YELLOW}⚠${NC} $rel_md → date indiquee '$date_in_file' mais commit recent ($last_commit)"
            STALE_DATES=$((STALE_DATES + 1))
        fi
    fi
done <<< "$MD_FILES"
if [[ "$STALE_DATES" -eq 0 ]]; then
    echo -e "  ${GREEN}✓ aucune date obsolete detectee${NC}"
fi
echo ""

# === CHECK 4 : Statuts contradictoires ===
echo -e "${BOLD}[4/4] Statuts contradictoires (a creer / a trancher / pas commence)${NC}"
CONTRADICTIONS=0
# Patterns qui devraient declencher une revue manuelle
PATTERNS=("à créer" "a creer" "à trancher" "a trancher" "🔴 À CRÉER" "non commencé" "non commence")
while IFS= read -r md_file; do
    [[ -z "$md_file" ]] && continue
    # Exclure CHANGELOG et fichiers de plan (BUILD_PLAN.md a des statuts legitimes)
    case "$md_file" in
        *CHANGELOG.md|*BUILD_PLAN.md|*PHASE_0_CHECKLIST.md|*ACTIONS*)
            continue ;;
    esac
    for pattern in "${PATTERNS[@]}"; do
        hits=$(grep -niE "$pattern" "$md_file" 2>/dev/null | head -3)
        if [[ -n "$hits" ]]; then
            rel_md="${md_file#$PROJECT_DIR/}"
            while IFS= read -r hit; do
                line_num=$(echo "$hit" | cut -d: -f1)
                content=$(echo "$hit" | cut -d: -f2- | sed 's/^ *//' | cut -c1-80)
                echo -e "  ${YELLOW}⚠${NC} $rel_md:$line_num → \"$content...\""
                CONTRADICTIONS=$((CONTRADICTIONS + 1))
            done <<< "$hits"
        fi
    done
done <<< "$MD_FILES"
if [[ "$CONTRADICTIONS" -eq 0 ]]; then
    echo -e "  ${GREEN}✓ aucun statut contradictoire detecte${NC}"
fi
echo ""

# === BILAN ===
TOTAL_ISSUES=$((BROKEN_LINKS + DELETED_REFS + STALE_DATES + CONTRADICTIONS))
echo -e "${BOLD}${CYAN}=== BILAN ===${NC}"
echo "  Liens casses          : $BROKEN_LINKS"
echo "  Fichiers supprimes    : $DELETED_REFS"
echo "  Dates obsoletes       : $STALE_DATES"
echo "  Statuts contradictoires : $CONTRADICTIONS"
echo "  ${BOLD}TOTAL : $TOTAL_ISSUES point(s) a verifier${NC}"
echo ""

if [[ "$TOTAL_ISSUES" -gt 0 ]]; then
    echo -e "${RED}${BOLD}Action requise :${NC} corriger chaque ligne signalee avant de finaliser la session."
    echo "Les ⚠ jaunes sont des avertissements (a verifier au cas par cas)."
    echo "Les ✗ rouges sont des erreurs (a corriger systematiquement)."
    exit 1
else
    echo -e "${GREEN}${BOLD}✓ Tous les .md sont coherents.${NC}"
    exit 0
fi
