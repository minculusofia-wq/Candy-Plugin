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
ECHEC=0
FOND=$(mktemp -d "${TMPDIR:-/tmp}/candy-essais.XXXXXX")
trap 'rm -rf "$FOND"' EXIT
for essai in "$RACINE"/tests/essais/[a-z]*.py; do
    nom=$(basename "$essai" .py)
    [ "$nom" = "commun" ] && continue
    ( python3 -I "$essai" "$RACINE/hooks" > "$FOND/$nom.sortie" 2>&1 < /dev/null; echo $? > "$FOND/$nom.code" ) &
done
wait
for essai in "$RACINE"/tests/essais/[a-z]*.py; do
    nom=$(basename "$essai" .py)
    [ "$nom" = "commun" ] && continue
    cat "$FOND/$nom.sortie" 2>/dev/null
    [ "$(cat "$FOND/$nom.code" 2>/dev/null)" = 0 ] || ECHEC=1
done
exit "$ECHEC"
