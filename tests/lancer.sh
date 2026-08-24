#!/bin/bash
#
# lancer.sh — rejoue tous les tests du plugin.
#
# Usage :  make test        (ou)  bash tests/lancer.sh
#
# Chaque fichier 0*-*.sh est un groupe de cas. Un groupe qui échoue n'arrête
# pas les autres : on veut la liste complète de ce qui casse, pas le premier.

cd "$(dirname "$0")/.."
ECHECS=0
GROUPES=0

if [ -t 1 ]; then
    VERT=$'\033[0;32m'; ROUGE=$'\033[0;31m'; GRAS=$'\033[1m'; NC=$'\033[0m'
else
    VERT=""; ROUGE=""; GRAS=""; NC=""
fi

echo "${GRAS}=== TESTS DU PLUGIN ===${NC}"

for groupe in tests/0*.sh; do
    GROUPES=$((GROUPES + 1))
    bash "$groupe" || ECHECS=$((ECHECS + 1))
done

echo
echo "${GRAS}=== RÉSULTAT ===${NC}"
if [ "$ECHECS" -eq 0 ]; then
    echo "  ${VERT}$GROUPES groupes, tout passe.${NC}"
    exit 0
fi
echo "  ${ROUGE}$ECHECS groupe(s) sur $GROUPES en échec.${NC}"
exit 1
