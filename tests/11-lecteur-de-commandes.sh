#!/bin/bash
#
# Les garde-fous qui lisent une commande ou un fichier comme le ferait bash :
# secrets (valeurs, lecture, git add), push, clôture de phase.
#
# Des centaines de cas : ils vivent dans tests/essais/*.py, un fichier par
# garde-fou, et ce groupe les lance tous, EN MÊME TEMPS (0.4.4 : secrets.py
# seul dure plus que les autres réunis). Chacun affiche ses cas et son bilan,
# dans l'ordre ; un essai qui n'a rendu aucun code compte comme un échec.

RACINE="$(cd "$(dirname "$0")/.." && pwd)"
source "$RACINE/tests/parallele.sh"
essai() { python3 -I "$1" "$RACINE/hooks"; }
ESSAIS=()
for f in "$RACINE"/tests/essais/[a-z]*.py; do
    [ "$(basename "$f")" = "commun.py" ] || ESSAIS+=("$f")
done
en_parallele essai "${ESSAIS[@]}"
[ "$ECHOUES" -eq 0 ]
