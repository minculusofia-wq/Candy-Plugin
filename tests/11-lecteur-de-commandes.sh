#!/bin/bash
#
# Les garde-fous qui lisent une commande ou un fichier comme le ferait bash :
# secrets (valeurs, lecture, git add), push, clôture de phase.
#
# Des centaines de cas : ils vivent dans tests/essais/*.py, un fichier par
# garde-fou, et ce groupe les lance tous. Chacun affiche ses cas et son bilan.

RACINE="$(cd "$(dirname "$0")/.." && pwd)"
ECHEC=0
for essai in "$RACINE"/tests/essais/[a-z]*.py; do
    [ "$(basename "$essai")" = "commun.py" ] && continue
    python3 -I "$essai" "$RACINE/hooks" || ECHEC=1
done
exit "$ECHEC"
