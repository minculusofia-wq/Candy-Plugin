#!/bin/bash
#
# Les hooks qui annoncent bloquer doivent bloquer.
#
# Le défaut d'origine : ils sortaient en 1. Claude Code ne bloque un outil que
# sur le code 2 ; tout autre code non nul est une erreur non bloquante, et
# l'action continue. Deux hooks affichaient donc « bloqué » pendant que la
# commande partait quand même.

source "$(dirname "$0")/aide.sh"
RACINE="$(cd "$(dirname "$0")/.." && pwd)"
BAC=$(mktemp -d)
trap 'rm -rf "$BAC"' EXIT

section "Commit de phase — la porte de sortie"
PHASE="$RACINE/hooks/rule12-phase-debug-required.sh"
MSG="$(printf 'Ph%sse 3 terminee' 'a')"
COMMIT_PHASE=$(entree_commande "git commit -m \"$MSG\"")

mkdir -p "$BAC/sans"
verifie "sans passage par la clôture, le commit est REFUSÉ" \
        2 "$(code_hook "$PHASE" "$COMMIT_PHASE" CLAUDE_PROJECT_DIR="$BAC/sans")"

mkdir -p "$BAC/avec" && touch "$BAC/avec/.claude-phase-debug-done"
verifie "avec le témoin de clôture, le commit passe" \
        0 "$(code_hook "$PHASE" "$COMMIT_PHASE" CLAUDE_PROJECT_DIR="$BAC/avec")"

verifie "le témoin est consommé : il ne vaut pas deux fois" \
        2 "$(code_hook "$PHASE" "$COMMIT_PHASE" CLAUDE_PROJECT_DIR="$BAC/avec")"

verifie "un commit ordinaire n'est jamais gêné" \
        0 "$(code_hook "$PHASE" "$(entree_commande 'git commit -m \"fix: petite correction\"')" CLAUDE_PROJECT_DIR="$BAC/sans")"

section "Contrôle avant push"
PUSH="$RACINE/hooks/validate-before-push.sh"

mkdir -p "$BAC/casse"
printf 'def casse(:\n    return 1\n' > "$BAC/casse/casse.py"
verifie "une erreur de syntaxe REFUSE le push" \
        2 "$(code_hook "$PUSH" '{}' CLAUDE_PROJECT_DIR="$BAC/casse")"

mkdir -p "$BAC/propre"
printf 'def ok():\n    return 1\n' > "$BAC/propre/ok.py"
verifie "un code valide laisse passer le push" \
        0 "$(code_hook "$PUSH" '{}' CLAUDE_PROJECT_DIR="$BAC/propre")"

# La suite de tests complète a été retirée de ce contrôle : sur un vrai projet
# elle transformait chaque push en plusieurs minutes d'attente, et un contrôle
# qu'on attend finit contourné. Le contrôle complet vit dans /verifier.
mkdir -p "$BAC/lent/tests"
printf 'def test_ko():\n    assert False\n' > "$BAC/lent/tests/test_ko.py"
verifie "des tests en échec ne bloquent PAS le push, par choix" \
        0 "$(code_hook "$PUSH" '{}' CLAUDE_PROJECT_DIR="$BAC/lent")"

section "Fin de tour — le contrôle si du code a bougé"
FIN="$RACINE/hooks/controle-si-code-modifie.sh"
export CLAUDE_PLUGIN_ROOT="$RACINE"

depot() {
    mkdir -p "$BAC/$1/tests"
    ( cd "$BAC/$1" && git init -q && git config user.email t@t.t && git config user.name t
      printf 'def test_ok():\n    assert True\n' > tests/test_ok.py
      echo "# doc" > README.md
      git add tests README.md && git commit -qm depart ) >/dev/null 2>&1
}

depot rien
verifie "rien de modifié : le hook se tait" \
        0 "$(code_hook "$FIN" "$(entree_fin_de_tour "$BAC/rien")")"

depot doc && echo "# suite" >> "$BAC/doc/README.md"
verifie "seule la doc bouge : le hook se tait" \
        0 "$(code_hook "$FIN" "$(entree_fin_de_tour "$BAC/doc")")"

depot code && printf 'def test_ko():\n    assert False\n' > "$BAC/code/tests/test_ko.py"
verifie "du code casse : la fin de tour est REFUSÉE" \
        2 "$(code_hook "$FIN" "$(entree_fin_de_tour "$BAC/code")")"

bilan
