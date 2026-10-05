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

# VERIFIER_A_BLANC=1 : liste les controles qui tourneraient, sans en lancer
# aucun (pour comparer deux versions de ce script sur un projet sans executer
# son code). Code 0, verdict « A BLANC ».
A_BLANC="${VERIFIER_A_BLANC:-0}"

lancer() {
    local nom="$1"; shift
    local neutre="$CODE_NEUTRE"; CODE_NEUTRE=""
    if [ "$A_BLANC" = 1 ]; then
        echo "  [A BLANC] $nom : $*"
        RESUME="${RESUME}  A BLANC  $nom\n"
        TROUVE=1
        return 0
    fi
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

# Ce que la cible <cible> d'un Makefile fait vraiment, en suivant ses cibles
# prealables (« test: test-back test-front »), les « $(MAKE) cible » et les
# « make -C dossier cible » : « pytest » si elle lance pytest, « backend » si
# elle entre dans backend/. Jusqu'a la 0.4.6, seule la recette de « test: »
# etait lue : « test: test-back » (test-back: cd backend && pytest) faisait
# relancer pytest depuis la racine, une seconde fois et sans sa configuration.
# Une cible qui ne l'appelle pas (« test: @true ») ne masque toujours rien.
ce_que_fait_la_cible() {  # ce_que_fait_la_cible <Makefile> <cible>
    python3 -I - "$1" "$2" <<'PYEOF' 2>/dev/null
import os, re, sys

def regles(chemin):
    r, courantes = {}, []
    try:
        lignes = open(chemin, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return r
    for l in lignes:
        if l.startswith("\t"):
            for c in courantes:
                r[c][1].append(l)
            continue
        m = re.match(r"^([\w.%/-]+(?:[ \t]+[\w.%/-]+)*)[ \t]*::?(?!=)(.*)$", l)
        if m:
            courantes = m.group(1).split()
            pre, _, ligne = m.group(2).partition(";")
            for c in courantes:
                r.setdefault(c, [[], []])
                r[c][0] += pre.split()
                if ligne.strip():
                    r[c][1].append(ligne)
        elif l.strip() and not l.lstrip().startswith("#"):
            courantes = []
    return r

trouve, vus = set(), set()

def suivre(makefile, cible, prof=0):
    if prof > 8 or (makefile, cible) in vus:
        return
    vus.add((makefile, cible))
    r = regles(makefile)
    if cible not in r:
        return
    pre, recette = r[cible]
    for p in pre:
        suivre(makefile, p, prof + 1)
    base = os.path.dirname(makefile)
    for l in recette:
        if "pytest" in l:
            trouve.add("pytest")
        if re.search(r"(^|[\s;&(])(cd|pushd)\s+(\./)?backend\b|-C\s*(\./)?backend\b|--directory[= ](\./)?backend\b", l):
            trouve.add("backend")
        # Un sous-make : ses options (-C dossier, -f fichier…), ses variables
        # (X=1) et ses cibles ; sans cible, la premiere regle du Makefile vise.
        for m in re.finditer(r"(?:\$\(MAKE\)|\$\{MAKE\}|\bmake\b)([^;&|)]*)", l):
            mots, dossier, cibles, k = m.group(1).split(), None, [], 0
            while k < len(mots):
                w = mots[k]
                if w in ("-C", "-f", "-I", "-o", "-W") and k + 1 < len(mots):
                    dossier = mots[k + 1] if w == "-C" else dossier
                    k += 2
                    continue
                if w.startswith("-C") and len(w) > 2:
                    dossier = w[2:]
                elif w.startswith("--directory="):
                    dossier = w.split("=", 1)[1]
                elif not w.startswith("-") and "=" not in w:
                    cibles.append(w)
                k += 1
            sous = os.path.join(base, dossier, "Makefile") if dossier else makefile
            if not cibles:
                cibles = [c for c in regles(sous) if not c.startswith(".")][:1]
            for c in cibles:
                suivre(sous, c, prof + 1)

suivre(sys.argv[1], sys.argv[2])
print(" ".join(sorted(trouve)))
PYEOF
}
PYTEST_PAR_MAKE=0
BACKEND_PAR_MAKE=""

# --- Makefile : la source de vérité si elle existe ---
if [ -f Makefile ]; then
    for cible in $CIBLES; do
        if grep -qE "^${cible}:" Makefile; then
            lancer "make $cible" make "$cible"
            FAIT=$(ce_que_fait_la_cible Makefile "$cible")
            [ "$cible" = test ] && [[ " $FAIT " == *" pytest "* ]] && PYTEST_PAR_MAKE=1
            [[ " $FAIT " == *" backend "* ]] && BACKEND_PAR_MAKE="$BACKEND_PAR_MAKE $cible"
        fi
    done
fi

# --- Backend dans un sous-dossier ---
if [ -f backend/Makefile ]; then
    for cible in $CIBLES; do
        # Deja lancee par la cible de la racine (make -C backend, cd backend) :
        # la relancer ferait tourner les memes tests deux fois.
        [[ " $BACKEND_PAR_MAKE " == *" $cible "* ]] && continue
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
if [ "$A_BLANC" = 1 ]; then
    echo "A BLANC : rien n'a ete lance."
    exit 0
fi
if [ "$ECHECS" -eq 0 ]; then
    echo "TOUT PASSE."
    exit 0
else
    echo "$ECHECS controle(s) en echec — le travail n'est PAS terminé."
    exit 1
fi
