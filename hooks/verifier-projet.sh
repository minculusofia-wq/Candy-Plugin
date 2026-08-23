#!/bin/bash
#
# verifier-projet.sh
#
# Contrôle universel : détecte tout seul comment vérifier le projet courant
# et renvoie un verdict lisible + un code retour exploitable.
#
# Fonctionne sans configuration sur n'importe quel projet, ancien ou nouveau.
#
# Usage :
#   ./verifier-projet.sh [PROJECT_DIR]
#
# Codes retour :
#   0 = tout passe
#   1 = au moins un contrôle échoue
#   2 = aucun moyen de vérification trouvé dans ce projet
#

set -u

PROJET="${1:-$PWD}"
cd "$PROJET" 2>/dev/null || { echo "Dossier introuvable : $PROJET"; exit 2; }

echo "=== CONTROLE DU PROJET ==="
echo "Projet : $PROJET"
echo

TROUVE=0
ECHECS=0
RESUME=""

lancer() {
    local nom="$1"; shift
    echo "--- $nom ---"
    if "$@" 2>&1 | tail -25; then
        local code=${PIPESTATUS[0]}
    else
        local code=${PIPESTATUS[0]}
    fi
    if [ "$code" -eq 0 ]; then
        echo "  [OK] $nom"
        RESUME="${RESUME}  OK     $nom\n"
    else
        echo "  [ECHEC] $nom"
        RESUME="${RESUME}  ECHEC  $nom\n"
        ECHECS=$((ECHECS+1))
    fi
    echo
    TROUVE=1
}

# --- Makefile : la source de vérité si elle existe ---
if [ -f Makefile ]; then
    for cible in test lint typecheck audit; do
        if grep -qE "^${cible}:" Makefile; then
            lancer "make $cible" make "$cible"
        fi
    done
fi

# --- Backend dans un sous-dossier ---
if [ "$TROUVE" -eq 0 ] && [ -f backend/Makefile ]; then
    for cible in test lint typecheck audit; do
        if grep -qE "^${cible}:" backend/Makefile; then
            lancer "backend: make $cible" make -C backend "$cible"
        fi
    done
fi

# --- Python sans Makefile ---
if [ "$TROUVE" -eq 0 ]; then
    PYTEST=""
    for p in .venv/bin/pytest venv/bin/pytest backend/.venv/bin/pytest; do
        [ -x "$p" ] && PYTEST="$p" && break
    done
    [ -z "$PYTEST" ] && command -v pytest >/dev/null 2>&1 && PYTEST="pytest"

    if [ -n "$PYTEST" ] && { [ -d tests ] || [ -d test ] || ls test_*.py >/dev/null 2>&1; }; then
        lancer "pytest" "$PYTEST" -q
    fi

    for r in .venv/bin/ruff venv/bin/ruff; do
        if [ -x "$r" ]; then lancer "ruff" "$r" check .; break; fi
    done
fi

# --- Node / JS ---
if [ "$TROUVE" -eq 0 ] && [ -f package.json ]; then
    if grep -q '"test"' package.json; then lancer "npm test" npm test --silent; fi
    if grep -q '"lint"' package.json; then lancer "npm run lint" npm run lint --silent; fi
fi

# --- Verdict ---
echo "=== VERDICT ==="
if [ "$TROUVE" -eq 0 ]; then
    echo "AUCUN MOYEN DE VERIFICATION TROUVE dans ce projet."
    echo
    echo "Rien ne permet de savoir si une modification casse quelque chose."
    echo "Avant tout autre travail sur ce projet : mettre en place un controle."
    exit 2
fi

printf "%b" "$RESUME"
echo
if [ "$ECHECS" -eq 0 ]; then
    echo "TOUT PASSE."
    exit 0
else
    echo "$ECHECS controle(s) en echec — le travail n'est PAS terminé."
    exit 1
fi
