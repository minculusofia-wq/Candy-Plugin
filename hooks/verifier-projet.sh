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
# « make -C dossier cible » :
#   pytest               elle lance pytest a la racine du projet ;
#   pytest-backend       elle le lance dans backend/ (cd backend, make -C backend) ;
#   make-backend:<c>     elle lance la cible <c> de backend/Makefile.
# Jusqu'a la 0.4.6, seule la recette de « test: » etait lue : « test: test-back »
# (test-back: cd backend && pytest) faisait relancer pytest depuis la racine.
# Un controle n'est saute que s'il est SUR d'etre couvert : un « cd backend »
# dans une cible d'installation faisait sauter les tests du backend (relecture
# de securite de la 0.5.0 : TOUT PASSE sur une suite rouge).
ce_que_fait_la_cible() {  # ce_que_fait_la_cible <Makefile> <cible>
    python3 -I - "$1" "$2" <<'PYEOF' 2>/dev/null
import os, re, sys

def variables(chemin):
    """Les variables du Makefile (X = …, X := …, X ?= …) : « $(PYTEST) -q »
    lance pytest sans en écrire le nom."""
    v = {}
    try:
        lignes = open(chemin, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return v
    for l in lignes:
        m = re.match(r"^(?:export\s+)?([A-Za-z_][\w.]*)\s*(?:[:?+]?=|::=)\s*(.*)$", l)
        if m and not l.startswith("\t"):
            v[m.group(1)] = m.group(2)
    return v

def developper(ligne, v):
    for _ in range(5):
        # Une variable inconnue du fichier ($(MAKE), une variable d'environnement)
        # reste telle quelle : vidée, « $(MAKE) -C backend test » n'était plus un sous-make.
        neuve = re.sub(r"\$[({]([A-Za-z_][\w.]*)[)}]", lambda m: v.get(m.group(1), m.group(0)), ligne)
        if neuve == ligne:
            break
        ligne = neuve
    return ligne

def regles(chemin):
    r, courantes = {}, []
    try:
        lignes = open(chemin, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return r
    v = variables(chemin)
    for l in lignes:
        if l.startswith("\t"):
            l = "\t" + developper(l[1:], v)
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
RACINE = os.path.abspath(".")
BACKEND = os.path.join(RACINE, "backend")
ENTRE_BACKEND = re.compile(r"(?:^|[\s;&(])(?:cd|pushd)\s+(?:\./)?backend/?(?=[\s;&|)]|$)")

def dossier_de(makefile):
    return os.path.abspath(os.path.dirname(makefile) or ".")

def suivre(makefile, cible, prof=0, dans_backend=None):
    if prof > 8 or (makefile, cible) in vus:
        return
    vus.add((makefile, cible))
    r = regles(makefile)
    if cible not in r:
        return
    if dans_backend is None:
        dans_backend = dossier_de(makefile) == BACKEND
    pre, recette = r[cible]
    for p in pre:
        suivre(makefile, p, prof + 1, dans_backend)
    base = os.path.dirname(makefile)
    for l in recette:
        cd = ENTRE_BACKEND.search(l)
        i_pytest = l.find("pytest")
        if i_pytest >= 0:
            # pytest après un « cd backend » de la même ligne tourne dans backend/
            ici = dans_backend or (cd is not None and cd.start() < i_pytest)
            trouve.add("pytest-backend" if ici else "pytest")
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
            if dossier is None and cd is not None and cd.start() < m.start():
                dossier = "backend"              # cd backend && make test
            sous = os.path.join(base, dossier, "Makefile") if dossier else makefile
            if not cibles:
                cibles = [c for c in regles(sous) if not c.startswith(".")][:1]
            vers_backend = dossier_de(sous) == BACKEND
            for c in cibles:
                if vers_backend:
                    trouve.add("make-backend:" + c)
                suivre(sous, c, prof + 1, vers_backend or dans_backend)

suivre(sys.argv[1], sys.argv[2])
print(" ".join(sorted(trouve)))
PYEOF
}
PYTEST_PAR_MAKE=0           # pytest lance a la racine par une cible test : couvert
PYTEST_BACKEND=0            # pytest lance dans backend/ : la racine tourne sans lui
BACKEND_PAR_MAKE=""         # cibles de backend/Makefile deja lancees par la racine

# --- Makefile : la source de vérité si elle existe ---
if [ -f Makefile ]; then
    for cible in $CIBLES; do
        if grep -qE "^${cible}:" Makefile; then
            lancer "make $cible" make "$cible"
            FAIT=$(ce_que_fait_la_cible Makefile "$cible")
            [ "$cible" = test ] && [[ " $FAIT " == *" pytest "* ]] && PYTEST_PAR_MAKE=1
            [ "$cible" = test ] && [[ " $FAIT " == *" pytest-backend "* ]] && PYTEST_BACKEND=1
            [[ " $FAIT " == *" make-backend:$cible "* ]] && BACKEND_PAR_MAKE="$BACKEND_PAR_MAKE $cible"
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
            # Elle lance pytest dans backend/ : celui de la racine tourne sans backend/.
            [ "$cible" = test ] && [[ " $(ce_que_fait_la_cible backend/Makefile test) " == *" pytest-backend "* ]] && PYTEST_BACKEND=1
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
    if [ "$PYTEST_BACKEND" -eq 1 ]; then
        # Les tests de backend/ ont deja tourne (cd backend, make -C backend) :
        # ceux de la racine tournent quand meme, sans eux — s'il y en a. Sans
        # fichier de test hors de backend/, pytest n'a rien a lancer, et sur
        # certains projets il rendait 0 sur « collected 0 items » : un vert qui
        # n'aurait rien teste.
        HORS_BACKEND=$(find . \( -name backend -o -name node_modules -o -name .venv -o -name venv \
            -o -name .git -o -name build -o -name dist -o -name site-packages \) -prune \
            -o \( -name 'test_*.py' -o -name '*_test.py' \) -print 2>/dev/null | head -1)
        [ -n "$HORS_BACKEND" ] && lancer "pytest (hors backend/)" "$PYTEST" -q -p no:cacheprovider --ignore=backend
    else
        lancer "pytest" "$PYTEST" -q -p no:cacheprovider
    fi
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
