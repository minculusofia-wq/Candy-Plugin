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
#   ./verifier-projet.sh [PROJECT_DIR] [--rapide]
#
# --rapide : mode fin de tour. Si le projet declare une cible « test-rapide »
# dans son Makefile, elle remplace « test ». Sans cette cible, rien ne change.
#
# Codes retour :
#   0 = tout passe
#   1 = au moins un contrôle échoue
#   2 = aucun moyen de vérification trouvé dans ce projet
#

set -u

PROJET=""
RAPIDE=0
for arg in "$@"; do
    if [ "$arg" = "--rapide" ]; then RAPIDE=1; else PROJET="$arg"; fi
done
[ -n "$PROJET" ] || PROJET="$PWD"
cd "$PROJET" 2>/dev/null || { echo "Dossier introuvable : $PROJET"; exit 2; }

echo "=== CONTROLE DU PROJET ==="
echo "Projet : $PROJET"
echo

TROUVE=0
ECHECS=0
RESUME=""

# CODE_NEUTRE : code retour qui signifie « ce controle n'a rien a faire ici ».
# Un seul outil en a un aujourd'hui : pytest, dont le 5 veut dire « aucun test
# collecte ». Se remet a vide apres chaque appel — il ne vaut que pour le
# controle qui suit.
CODE_NEUTRE=""

lancer() {
    local nom="$1"; shift
    local neutre="$CODE_NEUTRE"; CODE_NEUTRE=""
    local sortie code
    sortie="$("$@" 2>&1)"
    code=$?
    if [ -n "$neutre" ] && [ "$code" -eq "$neutre" ]; then
        return 0
    fi
    echo "--- $nom ---"
    printf '%s\n' "$sortie" | tail -25
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
# En fin de tour, un projet peut proposer un sous-ensemble rapide de sa suite
# sous le nom « test-rapide » : c'est alors lui qui tourne, pas la suite
# complete. Un controle qu'on attend finit contourne.
CIBLE_TEST=test
if [ "$RAPIDE" -eq 1 ] && [ -f Makefile ] && grep -qE "^test-rapide:" Makefile; then
    CIBLE_TEST=test-rapide
fi

if [ -f Makefile ]; then
    for cible in "$CIBLE_TEST" lint typecheck audit; do
        if grep -qE "^${cible}:" Makefile; then
            lancer "make $cible" make "$cible"
        fi
    done
fi

# --- Backend dans un sous-dossier ---
if [ -f backend/Makefile ]; then
    for cible in test lint typecheck audit; do
        if grep -qE "^${cible}:" backend/Makefile; then
            lancer "backend: make $cible" make -C backend "$cible"
        fi
    done
fi

# --- Python ---
PYTEST=""
for p in .venv/bin/pytest venv/bin/pytest backend/.venv/bin/pytest; do
    [ -x "$p" ] && PYTEST="$p" && break
done
if [ -z "$PYTEST" ] && command -v pytest >/dev/null 2>&1; then PYTEST="pytest"; fi

# On ne devine PAS a la place de pytest ou vivent les tests. Lister des dossiers
# ( . tests test ) rate les dispositions les plus repandues — tests/unit/,
# backend/tests/, src/tests/ — et laisse alors une suite cassee passer pour
# verte. Pytest, lui, sait deja lire les dossiers imbriques, conftest.py, le
# testpaths d'un pyproject.toml et les nommages personnalises.
#
# Son code 5 signifie « aucun test collecte » : le projet n'a pas de tests
# Python, ce controle n'existe pas ici — ni echec, ni controle trouve. C'est le
# cas de ce depot-ci, dont les tests sont des scripts shell.
if [ -n "$PYTEST" ]; then
    CODE_NEUTRE=5
    lancer "pytest" "$PYTEST" -q
fi

for r in .venv/bin/ruff venv/bin/ruff; do
    if [ -x "$r" ]; then lancer "ruff" "$r" check .; break; fi
done

# --- Node / JS ---
if [ -f package.json ]; then
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
