#!/bin/bash
#
# Le contrôle universel : il doit lancer TOUS les contrôles qu'il trouve,
# pas seulement la première famille rencontrée.
#
# Le défaut d'origine : chaque famille était conditionnée à « aucun contrôle
# trouvé jusqu'ici ». Un Makefile qui passe suffisait à masquer une suite de
# tests en échec, et le verdict tombait à « TOUT PASSE » en sortie 0.

source "$(dirname "$0")/aide.sh"
RACINE="$(cd "$(dirname "$0")/.." && pwd)"
CONTROLE="$RACINE/hooks/verifier-projet.sh"
BAC=$(mktemp -d)
trap 'rm -rf "$BAC"' EXIT

section "Contrôle universel — les quatre verdicts"

# --- un Makefile qui passe, une suite Python et une suite Node en échec ---
mkdir -p "$BAC/melange/tests"
printf 'test:\n\t@true\n' > "$BAC/melange/Makefile"
printf 'def test_ko():\n    assert False\n' > "$BAC/melange/tests/test_ko.py"
printf '{"name":"m","scripts":{"test":"exit 1"}}\n' > "$BAC/melange/package.json"

SORTIE=$(bash "$CONTROLE" "$BAC/melange" 2>&1); CODE=$?
verifie "un Makefile qui passe ne masque plus le reste" 1 "$CODE"
verifie "  la suite Python en échec est signalée" \
        1 "$(echo "$SORTIE" | grep -c 'ECHEC  pytest')"
verifie "  la suite Node en échec est signalée" \
        1 "$(echo "$SORTIE" | grep -c 'ECHEC  npm test')"
verifie "  le contrôle qui passe reste listé" \
        1 "$(echo "$SORTIE" | grep -c 'OK     make test')"
verifie "  le verdict ne dit pas que tout passe" \
        0 "$(echo "$SORTIE" | grep -c 'TOUT PASSE')"

# --- sans Makefile : les deux familles doivent tourner quand même ---
mkdir -p "$BAC/deux/tests"
printf 'def test_ko():\n    assert False\n' > "$BAC/deux/tests/test_ko.py"
printf '{"name":"d","scripts":{"test":"exit 1"}}\n' > "$BAC/deux/package.json"
SORTIE=$(bash "$CONTROLE" "$BAC/deux" 2>&1)
verifie "sans Makefile, Python et Node sont tous deux lancés" \
        2 "$(echo "$SORTIE" | grep -c 'ECHEC ')"

# --- tout vert ---
mkdir -p "$BAC/vert/tests"
printf 'def test_ok():\n    assert True\n' > "$BAC/vert/tests/test_ok.py"
printf '{"name":"v","scripts":{"test":"exit 0"}}\n' > "$BAC/vert/package.json"
bash "$CONTROLE" "$BAC/vert" >/dev/null 2>&1
verifie "un projet sain sort en 0" 0 $?

# --- un dossier « tests » qui ne contient PAS de tests Python ---
# Trouvé en écrivant ces tests : le contrôle lançait pytest dès qu'un dossier
# tests existait. Sur ce dépôt-ci, dont les tests sont des scripts shell, pytest
# ne collectait rien, sortait en 5, et le projet était déclaré en échec.
mkdir -p "$BAC/shell/tests"
printf 'test:\n\t@true\n' > "$BAC/shell/Makefile"
printf '#!/bin/bash\nexit 0\n' > "$BAC/shell/tests/cas.sh"
SORTIE=$(bash "$CONTROLE" "$BAC/shell" 2>&1); CODE=$?
verifie "un dossier tests sans test Python ne déclenche pas pytest" \
        0 "$(echo "$SORTIE" | grep -c 'pytest')"
verifie "  et le projet reste au vert" 0 "$CODE"

# --- rien à quoi se fier : le cas que rien d'autre ne signale ---
mkdir -p "$BAC/vide"
bash "$CONTROLE" "$BAC/vide" >/dev/null 2>&1
verifie "un projet sans aucun moyen de vérification sort en 2" 2 $?

bilan
