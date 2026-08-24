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

COEUR=$(mktemp -t md-audit-XXXXXX.py)
trap 'rm -f "$COEUR"' EXIT
cat > "$COEUR" <<'PYFIN'
import sys, re, os

MODE = sys.argv[1]
PROJET = os.path.abspath(sys.argv[2])
fichiers = [l for l in sys.stdin.read().splitlines() if l.strip()]

# --- Usage vs mention -------------------------------------------------------
# Meme piege que relire-ma-reponse.sh : un document qui EXPLIQUE ce que ce
# controle attrape se faisait signaler par lui. Sont donc neutralises avant
# jugement : blocs de code, extraits entre accents graves, segments entre
# guillemets francais ou droits. Les blocs sont remplaces par des lignes vides
# pour que les numeros de ligne restent justes.
def neutraliser(contenu):
    contenu = re.sub(r"```.*?```",
                     lambda m: "\n" * m.group(0).count("\n"),
                     contenu, flags=re.S)
    return contenu

def sans_citations(ligne):
    ligne = re.sub(r"`[^`]*`", " ", ligne)
    ligne = re.sub(r"«[^»]*»", " ", ligne)
    ligne = re.sub(r'"[^"\n]*"', " ", ligne)
    return ligne

LIEN = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
STATUTS = re.compile(r"(à créer|a creer|à trancher|a trancher|non commencé|non commence)", re.I)

vus = set()
for f in fichiers:
    try:
        contenu = open(f, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    rel = os.path.relpath(os.path.abspath(f), PROJET)
    for num, brute in enumerate(neutraliser(contenu).splitlines(), 1):
        ligne = sans_citations(brute)
        if MODE == "liens":
            for cible in LIEN.findall(ligne):
                if cible.startswith(("http://", "https://", "mailto:", "#")):
                    continue
                chemin = cible.split("#")[0].strip()
                if not chemin:
                    continue
                if os.path.exists(os.path.join(os.path.dirname(f), chemin)):
                    continue
                cle = (rel, num, chemin)
                if cle in vus:
                    continue
                vus.add(cle)
                print("%s:%s\t%s" % (rel, num, chemin))
        else:
            m = STATUTS.search(ligne)
            if not m:
                continue
            cle = (rel, num)
            if cle in vus:
                continue
            vus.add(cle)
            extrait = brute.strip()[:80]
            print("%s:%s\t%s" % (rel, num, extrait))
PYFIN

TOTAL_MD=$(echo "$MD_FILES" | wc -l | tr -d ' ')
echo -e "${CYAN}Scan de $TOTAL_MD fichiers .md...${NC}"
echo ""

# === CHECK 1 : Liens markdown casses ===
echo -e "${BOLD}[1/4] Liens markdown casses${NC}"
LIENS_OUT=$(printf '%s\n' "$MD_FILES" | python3 "$COEUR" liens "$PROJECT_DIR" 2>/dev/null)
if [[ -n "$LIENS_OUT" ]]; then
    BROKEN_LINKS=$(printf '%s\n' "$LIENS_OUT" | wc -l | tr -d ' ')
    while IFS=$'\t' read -r ou quoi; do
        [[ -z "$ou" ]] && continue
        echo -e "  ${RED}✗${NC} $ou → lien casse : $quoi"
    done <<< "$LIENS_OUT"
else
    BROKEN_LINKS=0
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
STATUTS_MD=$(printf '%s\n' "$MD_FILES" | grep -vE 'CHANGELOG\.md|BUILD_PLAN\.md|PHASE_0_CHECKLIST\.md|ACTIONS' || true)
STATUTS_OUT=$(printf '%s\n' "$STATUTS_MD" | python3 "$COEUR" statuts "$PROJECT_DIR" 2>/dev/null)
if [[ -n "$STATUTS_OUT" ]]; then
    CONTRADICTIONS=$(printf '%s\n' "$STATUTS_OUT" | wc -l | tr -d ' ')
    while IFS=$'\t' read -r ou quoi; do
        [[ -z "$ou" ]] && continue
        echo -e "  ${YELLOW}⚠${NC} $ou → \"$quoi\""
    done <<< "$STATUTS_OUT"
else
    CONTRADICTIONS=0
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
