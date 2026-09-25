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

# CODE_NEUTRE : code retour qui signifie « ce controle n'a rien a faire ici ».
# Un seul outil en a un aujourd'hui : pytest, dont le 5 veut dire « aucun test
# collecte ». Se remet a vide apres chaque appel — il ne vaut que pour le
# controle qui suit.
CODE_NEUTRE=""

lancer() {
    local nom="$1"; shift
    local neutre="$CODE_NEUTRE"; CODE_NEUTRE=""
    # La sortie va dans un fichier, pas dans « $( ) » : un processus laisse en
    # arriere-plan par les tests tenait la capture ouverte, et le controle
    # attendait jusqu'a la fin du budget du hook Stop. bash attend la commande,
    # pas ses enfants. Entree fermee : un test qui attend le clavier ne pend pas.
    local sortie code
    # Sans fichier temporaire (disque plein), le controle n'a pas tourne : c'est
    # un echec, pas une absence de controle, qui passerait pour un vert.
    if sortie=$(mktemp "${TMPDIR:-/tmp}/verifier-projet.XXXXXX"); then
        "$@" > "$sortie" 2>&1 < /dev/null
        code=$?
    else
        sortie=/dev/null
        echo "impossible de creer un fichier temporaire : $nom n'a pas tourne"
        code=1
    fi
    if [ -n "$neutre" ] && [ "$code" -eq "$neutre" ]; then
        [ "$sortie" = /dev/null ] || rm -f "$sortie"
        return 0
    fi
    echo "--- $nom ---"
    tail -25 "$sortie"
    [ "$sortie" = /dev/null ] || rm -f "$sortie"
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

# L'audit des dependances (pip-audit, npm audit) va sur le reseau et peut
# installer des paquets : le controle de fin de tour le coupe
# (VERIFIER_SANS_AUDIT=1). /verifier le garde.
CIBLES="test lint typecheck audit"
[ "${VERIFIER_SANS_AUDIT:-0}" = 1 ] && CIBLES="test lint typecheck"

# La cible « test » du Makefile lance-t-elle pytest elle-meme ? Alors pytest
# n'est pas relance plus bas : jusqu'a la 0.3.4, il tournait deux fois. Une
# cible qui ne l'appelle pas (« test: @true ») ne masque toujours rien.
recette_test_lance_pytest() {
    awk '/^test:/ { dans = 1; if ($0 ~ /pytest/) { print "oui"; exit } ; next }
         dans && /^[^\t]/ { dans = 0 }
         dans && /pytest/ { print "oui"; exit }' Makefile 2>/dev/null | grep -q oui
}
PYTEST_PAR_MAKE=0

# --- Makefile : la source de vérité si elle existe ---
if [ -f Makefile ]; then
    for cible in $CIBLES; do
        if grep -qE "^${cible}:" Makefile; then
            lancer "make $cible" make "$cible"
            [ "$cible" = test ] && recette_test_lance_pytest && PYTEST_PAR_MAKE=1
        fi
    done
fi

# --- Backend dans un sous-dossier ---
if [ -f backend/Makefile ]; then
    for cible in $CIBLES; do
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
if [ -n "$PYTEST" ] && [ "$PYTEST_PAR_MAKE" -eq 0 ]; then
    CODE_NEUTRE=5
    # -p no:cacheprovider : ne rien ecrire dans le projet. Sans cette option,
    # pytest depose un dossier .pytest_cache chez l'utilisateur — y compris dans
    # un projet qui n'a pas une seule ligne de Python. Un controle ne salit pas
    # ce qu'il controle.
    lancer "pytest" "$PYTEST" -q -p no:cacheprovider
fi

for r in .venv/bin/ruff venv/bin/ruff; do
    if [ -x "$r" ]; then lancer "ruff" "$r" check .; break; fi
done

# --- Node / JS ---
if [ -f package.json ]; then
    # Le script « test » que cree npm init (« no test specified ») n'est pas un
    # test : il faisait echouer chaque controle, donc chaque fin de tour. Un
    # package.json illisible, lui, lance npm test : son echec se voit.
    SCRIPT_TEST=$(python3 -I -c 'import json
try:
    t = (json.load(open("package.json")).get("scripts") or {}).get("test") or ""
except Exception:
    t = "illisible"
print("" if "no test specified" in str(t) else t)' 2>/dev/null)
    if [ -n "$SCRIPT_TEST" ]; then lancer "npm test" npm test --silent; fi
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
