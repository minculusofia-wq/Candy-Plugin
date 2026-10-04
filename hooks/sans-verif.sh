#!/bin/bash
#
# sans-verif.sh (PreToolUse : Bash, Monitor)
#
# Refuse un git qui sauterait les hooks du dépôt. Un pre-commit qui refuse un
# commit incohérent indique souvent lui-même son contournement (« git commit
# --no-verify ») ; rien n'empêchait Claude de le taper par réflexe, sans bruit.
#
# Refusé, sur commit, push, merge, pull, cherry-pick, rebase et am :
#   - --no-verify, et ses abréviations que git accepte (--no-verif) ;
#   - -n de git commit et de git am (pour les autres, -n est autre chose) ;
#   - -c / --config-env sur core.hooksPath ou include (la ligne de commande
#     passe devant la config du dépôt) ;
#   - HUSKY, SKIP, GIT_CONFIG_PARAMETERS, et GIT_CONFIG_KEY_n quand il nomme
#     core.hooksPath ou include, posés pour lui (préfixe, env, export sur la
#     même ligne, ou préfixe d'un shell, d'un interprète ou de make qu'il
#     lance ; sur une autre commande — SKIP=1 pytest — il ne vaut que pour elle) ;
#   - git rebase -x / --exec, git submodule foreach, git bisect run, un alias
#     shell, dont la commande ferait l'un des précédents — ou dont le git
#     lanceur pose lui-même core.hooksPath ou HUSKY : git le transmet aux git
#     qu'il lance ; un alias en chaîne, dont chaque git d'un alias shell.
# Refusé aussi : git config qui écrit, retire ou édite core.hooksPath ou include. Les
# lectures passent. Une installation de hooks par core.hooksPath se tape donc
# à la main, une fois, par l'utilisateur.
#
# La commande est lue par analyse-commande.py (mode « sans-verif ») comme bash
# la lit : sudo, env, bash -c, $( ), eval, <<EOF, alias git… Jamais sur son
# texte brut : un message de commit qui cite --no-verify n'est pas refusé.
#
# LIMITE ASSUMÉE : ce garde arrête le réflexe, pas un contournement voulu. Une
# variable (F=--no-verify; git commit $F), un script, un autre langage (un
# script Python), set -a, un chmod -x ou un mv du hook, une édition directe de
# .git/config passent. Passent aussi un nom de commande calculé
# ($(which git) commit …) et les lanceurs que l'analyseur ne connaît pas
# (xcrun git, arch -arm64 git, script -q /dev/null git). Un eval dont le texte
# n'est connu qu'à l'exécution est jugé sur son texte, puis sur la ligne sans
# ses messages de commit ni ses <<EOF. Passent encore (relecture
# de sécurité du 2026-10-04, laissés tels quels : des contournements voulus,
# pas des réflexes) : l'expansion d'accolades (git {commit,-n}), un alias créé
# sur la même ligne, une commande envoyée à bash par un tube ou par <( ), un
# argument calculé (git commit $(echo …)), GIT_CONFIG_GLOBAL vers un fichier,
# coproc, difftool -x, core.pager, et les variables d'arrêt d'autres
# gestionnaires que husky et pre-commit (LEFTHOOK, OVERCOMMIT_DISABLE), et une
# variable posée dans le texte d'env -S (env -S 'HUSKY=0 git commit'). Refusés
# par prudence : un préfixe sur make ou sur un script (SKIP=1 make test && git
# commit), qui transmettent la variable à des git qu'on ne voit pas.
#
# Le message est un texte fixe : ni chemin ni nom n'y figure (la raison d'un
# refus arrive à Claude, et un nom choisi y deviendrait une consigne). Un
# garde-fou qui ne peut pas lire son entrée REFUSE, comme protect-secrets.sh.

set -u
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)

VERDICT=$(printf '%s' "$INPUT" | python3 -I "$H/analyse-commande.py" sans-verif 2>/dev/null) || {
    echo "Action refusee : ce garde-fou n'a pas pu lire l'action (Python introuvable ou en panne)." >&2
    echo "Reparer Python, puis relancer. Un garde-fou qui ne voit rien ne laisse rien passer." >&2
    exit 2
}

if [[ "$VERDICT" == "CONTOURNE" ]]; then
    echo "BLOCKED" >&2
    echo "" >&2
    echo "Commande refusee : elle sauterait les hooks git du depot (--no-verify, -n de git commit ou git am," >&2
    echo "core.hooksPath ou include passe par -c ou --config-env, GIT_CONFIG_*, HUSKY ou SKIP, ou git config" >&2
    echo "qui change core.hooksPath)." >&2
    echo "Si un hook a refuse : lire ce qu'il refuse, corriger, puis commiter normalement." >&2
    echo "Un contournement voulu se decide par l'utilisateur, qui tape la commande lui-meme dans son terminal." >&2
    exit 2
fi

exit 0
